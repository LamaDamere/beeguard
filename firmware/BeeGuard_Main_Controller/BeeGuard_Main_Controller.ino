/*
 * BeeGuard — ESP32 #1 (Main Controller) — v4.0
 *
 * WHAT CHANGED vs v3.0 (all requested fixes):
 *  1. SAFE BOOT: every actuator is driven to a known state at startup so
 *     nothing twitches on power-up. Relays are ACTIVE-LOW, so they are held
 *     HIGH (= OFF) *before* pinMode() to avoid the usual power-on glitch.
 *  2. RFID now drives the LOCK servo (GPIO19), NOT the door. Any card toggles
 *     the hive lock (1st scan = unlock, 2nd = lock) and every scan is mirrored
 *     to Firebase under /security + /rfid_logs so the app updates live.
 *  3. HONEY COLLECTION: opens the door + runs the smoke pump for 4 s, then
 *     leaves the door OPEN (no automatic closing). A separate stop command
 *     (collect_honey=false) closes it manually.
 *  4. FEEDING is volume-based: the app writes commands/feed_ml (50 or 100) and
 *     the ESP runs the pump for the mapped time (0.12 s/ml -> 50ml=6s,100ml=12s).
 *  5. ENTRANCE (hornet) open/narrow is driven cleanly from commands/entrance.
 *
 * ─── GPIO MAPPING ─────────────────────────────────────────
 * Main Door Servo (Honey Collection)  → GPIO 18
 * Lock Servo                          → GPIO 19
 * Entrance Servo                      → GPIO 13
 * Feeding Pump Relay                  → GPIO 33  (ACTIVE LOW)
 * Smoke Pump Relay                    → GPIO 32  (ACTIVE LOW)
 * Ultrasonic TRIG                     → GPIO 26
 * Ultrasonic ECHO                     → GPIO 16
 * HX711 DT                            → GPIO 17
 * HX711 SCK                           → GPIO 15
 * RFID SDA (SS)                       → GPIO 5
 * RFID SCK                            → GPIO 14
 * RFID MOSI                           → GPIO 25
 * RFID MISO                           → GPIO 27
 * RFID RST                            → GPIO 4
 *
 * Libraries: Firebase ESP32 Client (Mobizt), ESP32Servo, HX711 (Bogdan
 * Necula), MFRC522 (GithubCommunity).
 */

#include <WiFi.h>
#include <esp_now.h>
#include <Firebase_ESP_Client.h>
#include <ESP32Servo.h>
#include <HX711.h>
#include <SPI.h>
#include <MFRC522.h>

// ─── WiFi Credentials ─────────────────────────────────────
#define WIFI_SSID     "GP"
#define WIFI_PASSWORD "123456789"

// ─── Firebase ─────────────────────────────────────────────
#define API_KEY      "AIzaSyCqzB6EBkAenCuURUXDoji7N67xjDTb8SI"
#define DATABASE_URL "https://beeguard-smartbee-default-rtdb.europe-west1.firebasedatabase.app"

// ─── GPIO Pins ────────────────────────────────────────────
#define SERVO_DOOR_PIN      18   // Honey collection door
#define SERVO_LOCK_PIN      19   // Hive lock
#define SERVO_ENTRANCE_PIN  13   // Entrance narrowing

#define RELAY_FEED_PIN      33   // Feeding pump  (ACTIVE LOW)
#define RELAY_SMOKE_PIN     32   // Smoke pump    (ACTIVE LOW)

#define TRIG_PIN            26   // Ultrasonic
#define ECHO_PIN            16

#define HX711_DT            17   // Load cell
#define HX711_SCK           15

#define RFID_SS_PIN         5
#define RFID_RST_PIN        4

// ─── Servo angles (named so they're easy to flip if a servo is mounted
//     the other way round) ─────────────────────────────────
#define DOOR_CLOSED_ANGLE     0
#define DOOR_OPEN_ANGLE       180
#define LOCK_LOCKED_ANGLE     90     // boot / secured position
#define LOCK_UNLOCKED_ANGLE   180
#define ENTRANCE_OPEN_ANGLE   0
#define ENTRANCE_NARROW_ANGLE 180

// ─── Timing ───────────────────────────────────────────────
#define SMOKE_DURATION_MS   4000UL  // smoke pump burst during honey collection
#define FEED_MS_PER_ML      120UL   // 0.12 s/ml -> 50ml=6s, 100ml=12s

// ─── Ultrasonic container measurements ────────────────────
#define SENSOR_TO_TOP    4.0    // cm, sensor to top of container
#define CONTAINER_HEIGHT 3.5    // cm

// ─── Scale calibration ────────────────────────────────────
#define SCALE_CALIBRATION_FACTOR -7050.0

// ─── Feeding data structure ───────────────────────────────
struct FeedingData {
  float distance;
  float waterHeight;
  float percentage;
};

// ─── Objects ──────────────────────────────────────────────
FirebaseData   fbdo;
FirebaseAuth   auth;
FirebaseConfig config;
Servo          servoDoor;
Servo          servoLock;
Servo          servoEntrance;
HX711          scale;
MFRC522        rfid(RFID_SS_PIN, RFID_RST_PIN);

// ─── Timing ───────────────────────────────────────────────
unsigned long lastSensorUpload = 0;
const unsigned long UPLOAD_INTERVAL = 30000; // 30 seconds

// ─── State tracking ───────────────────────────────────────
bool   doorOpen         = false;  // honey door
bool   lockState        = true;   // true = LOCKED (secure boot default)
String entranceState    = "open";
bool   lastCollectHoney = false;
bool   lastHornetState  = false;  // rising-edge guard for hornet response

// ─── ESP-NOW received data ────────────────────────────────
float  receivedTemp       = 0.0;
float  receivedHumidity   = 0.0;
String receivedSound      = "Normal";
int    receivedConfidence = 0;
bool   hornetDetected     = false;

// ─── ESP-NOW data structures ──────────────────────────────
typedef struct {
  float temperature;
  float humidity;
  char  soundResult[20];
  int   confidence;
} SensorData;

typedef struct {
  bool hornetDetected;
} CamData;

SensorData incomingSensor;
CamData    incomingCam;

// ═══════════════════════════════════════════════════════════
// SMALL HELPERS
// ═══════════════════════════════════════════════════════════

String uptimeStamp() {
  return String(millis() / 1000) + "s";
}

// Sweep a servo smoothly from one angle to another.
void sweepServo(Servo &s, int fromAngle, int toAngle) {
  int step = (toAngle >= fromAngle) ? 5 : -5;
  for (int pos = fromAngle; (step > 0) ? (pos <= toAngle) : (pos >= toAngle); pos += step) {
    s.write(pos);
    delay(15);
  }
  s.write(toAngle);
}

// ═══════════════════════════════════════════════════════════
// HIVE LOCK (RFID) — GPIO19
// ═══════════════════════════════════════════════════════════

void publishLockState() {
  Firebase.RTDB.setBool(&fbdo, "/security/locked", lockState);
}

void unlockHive() {
  Serial.println("[LOCK] Unlocking");
  sweepServo(servoLock, LOCK_LOCKED_ANGLE, LOCK_UNLOCKED_ANGLE);
  lockState = false;
  publishLockState();
  Serial.println("[LOCK] Unlocked");
}

void lockHive() {
  Serial.println("[LOCK] Locking");
  sweepServo(servoLock, LOCK_UNLOCKED_ANGLE, LOCK_LOCKED_ANGLE);
  lockState = true;
  publishLockState();
  Serial.println("[LOCK] Locked");
}

// ═══════════════════════════════════════════════════════════
// ENTRANCE (Hornet) — GPIO13
// ═══════════════════════════════════════════════════════════

void openEntrance() {
  if (entranceState == "open") return;
  Serial.println("[ENTRANCE] Opening");
  sweepServo(servoEntrance, ENTRANCE_NARROW_ANGLE, ENTRANCE_OPEN_ANGLE);
  entranceState = "open";
  Firebase.RTDB.setString(&fbdo, "/hornet_detection/entrance_status", "open");
  Firebase.RTDB.setString(&fbdo, "/commands/entrance", "open");
  Serial.println("[ENTRANCE] Open");
}

void narrowEntrance() {
  if (entranceState == "narrow") return;
  Serial.println("[ENTRANCE] Narrowing");
  sweepServo(servoEntrance, ENTRANCE_OPEN_ANGLE, ENTRANCE_NARROW_ANGLE);
  entranceState = "narrow";
  Firebase.RTDB.setString(&fbdo, "/hornet_detection/entrance_status", "narrow");
  Firebase.RTDB.setString(&fbdo, "/commands/entrance", "narrow");
  Serial.println("[ENTRANCE] Narrowed");
}

// ═══════════════════════════════════════════════════════════
// HONEY COLLECTION — door GPIO18 + smoke GPIO32
// ═══════════════════════════════════════════════════════════

// Open the door, run smoke for 4 s, then LEAVE THE DOOR OPEN.
void collectHoney() {
  Serial.println("[HONEY] Start — opening door");
  sweepServo(servoDoor, DOOR_CLOSED_ANGLE, DOOR_OPEN_ANGLE);
  doorOpen = true;
  Firebase.RTDB.setBool(&fbdo, "/hive_status/door_open", true);

  // Smoke burst (ACTIVE LOW relay: LOW = ON).
  Serial.println("[HONEY] Smoke pump ON (4s)");
  digitalWrite(RELAY_SMOKE_PIN, LOW);
  Firebase.RTDB.setBool(&fbdo, "/commands/smoke_pump", true);
  delay(SMOKE_DURATION_MS);
  digitalWrite(RELAY_SMOKE_PIN, HIGH);
  Firebase.RTDB.setBool(&fbdo, "/commands/smoke_pump", false);
  Serial.println("[HONEY] Smoke pump OFF — door stays OPEN");
}

// Manual close (collect_honey=false). Smoke is already off; just close.
void stopHoneyCollection() {
  Serial.println("[HONEY] Stop — closing door");
  digitalWrite(RELAY_SMOKE_PIN, HIGH); // safety: ensure smoke off
  Firebase.RTDB.setBool(&fbdo, "/commands/smoke_pump", false);
  sweepServo(servoDoor, DOOR_OPEN_ANGLE, DOOR_CLOSED_ANGLE);
  doorOpen = false;
  Firebase.RTDB.setBool(&fbdo, "/hive_status/door_open", false);
  Serial.println("[HONEY] Door closed");
}

// ═══════════════════════════════════════════════════════════
// FEEDING — pump GPIO33, volume-based
// ═══════════════════════════════════════════════════════════

void feedBees(int ml) {
  unsigned long runMs = (unsigned long)ml * FEED_MS_PER_ML;
  Serial.printf("[FEED] Dispensing %d ml (%lu ms)\n", ml, runMs);

  Firebase.RTDB.setBool(&fbdo, "/commands/pump", true); // status echo -> app
  digitalWrite(RELAY_FEED_PIN, LOW);   // ACTIVE LOW = ON
  delay(runMs);
  digitalWrite(RELAY_FEED_PIN, HIGH);  // OFF
  Firebase.RTDB.setBool(&fbdo, "/commands/pump", false);

  // One-shot: clear the request so it doesn't re-trigger next loop.
  Firebase.RTDB.setInt(&fbdo, "/commands/feed_ml", 0);
  Serial.println("[FEED] Done");
}

// ═══════════════════════════════════════════════════════════
// ULTRASONIC — WATER/FOOD LEVEL
// ═══════════════════════════════════════════════════════════

FeedingData readFeedingLevel() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  long duration = pulseIn(ECHO_PIN, HIGH, 30000);
  float distance = duration * 0.034 / 2.0;

  float waterHeight = CONTAINER_HEIGHT - (distance - SENSOR_TO_TOP);
  waterHeight = constrain(waterHeight, 0.0, CONTAINER_HEIGHT);

  float percentage = (waterHeight / CONTAINER_HEIGHT) * 100.0;
  percentage = constrain(percentage, 0.0, 100.0);

  FeedingData data;
  data.distance    = distance;
  data.waterHeight = waterHeight;
  data.percentage  = percentage;
  return data;
}

// ═══════════════════════════════════════════════════════════
// HX711 — HONEY PRODUCTION
// ═══════════════════════════════════════════════════════════

float readWeight() {
  if (scale.is_ready()) return scale.get_units(5);
  return 0.0;
}

// ═══════════════════════════════════════════════════════════
// HEALTH SCORE
// ═══════════════════════════════════════════════════════════

int calcHealthScore(float temp, float hum, float weight, String sound) {
  int score = 100;
  if (temp > 36.0 || temp < 32.0) score -= 20;
  if (hum  > 75.0 || hum  < 40.0) score -= 15;
  if (sound != "Normal")           score -= 30;
  if (hornetDetected)              score -= 20;
  if (weight < 5.0)                score -= 15;
  return constrain(score, 0, 100);
}

// ═══════════════════════════════════════════════════════════
// ALERTS
// ═══════════════════════════════════════════════════════════

void pushAlert(const String &type, const String &message) {
  String path = "/alerts/" + type + "_" + String(millis());
  Firebase.RTDB.setString(&fbdo, path + "/type",      type);
  Firebase.RTDB.setString(&fbdo, path + "/message",   message);
  Firebase.RTDB.setString(&fbdo, path + "/timestamp", "just now");
  Firebase.RTDB.setBool(&fbdo,   path + "/read",      false);
}

// ═══════════════════════════════════════════════════════════
// FIREBASE — UPLOAD SENSOR DATA
// ═══════════════════════════════════════════════════════════

void uploadSensorData() {
  FeedingData feeding = readFeedingLevel();
  float weight        = readWeight();
  int   health        = calcHealthScore(receivedTemp, receivedHumidity, weight, receivedSound);
  String timeStr      = uptimeStamp();

  // hive_status
  Firebase.RTDB.setFloat(&fbdo,  "/hive_status/temperature",     receivedTemp);
  Firebase.RTDB.setFloat(&fbdo,  "/hive_status/humidity",        receivedHumidity);
  Firebase.RTDB.setFloat(&fbdo,  "/hive_status/weight",          weight);
  Firebase.RTDB.setFloat(&fbdo,  "/hive_status/water_level",     feeding.percentage);
  Firebase.RTDB.setFloat(&fbdo,  "/hive_status/water_height_cm", feeding.waterHeight);
  Firebase.RTDB.setString(&fbdo, "/hive_status/sound_result",     receivedSound);
  Firebase.RTDB.setInt(&fbdo,    "/hive_status/sound_confidence", receivedConfidence);
  Firebase.RTDB.setInt(&fbdo,    "/hive_status/health_score",     health);
  Firebase.RTDB.setBool(&fbdo,   "/hive_status/door_open",        doorOpen);
  Firebase.RTDB.setString(&fbdo, "/hive_status/last_sync",        timeStr);

  // Honey production
  Firebase.RTDB.setFloat(&fbdo, "/production/today_weight", weight);

  // hornet_detection
  Firebase.RTDB.setBool(&fbdo, "/hornet_detection/detected", hornetDetected);

  // ai_status (mirrors ESP32 #2)
  Firebase.RTDB.setString(&fbdo, "/ai_status/sound_result",  receivedSound);
  Firebase.RTDB.setInt(&fbdo,    "/ai_status/confidence",    receivedConfidence);
  Firebase.RTDB.setString(&fbdo, "/ai_status/last_analysis", timeStr);

  // Feeding warnings
  if (feeding.percentage < 10.0) {
    pushAlert("water", "CRITICAL: Feeding level below 10%!");
  } else if (feeding.percentage < 20.0) {
    pushAlert("water", "WARNING: Feeding level below 20%");
  }

  Serial.printf("[Firebase] Temp:%.1f Hum:%.1f Weight:%.2f Feed:%.0f%% Lock:%s Door:%s\n",
                receivedTemp, receivedHumidity, weight, feeding.percentage,
                lockState ? "LOCKED" : "UNLOCKED", doorOpen ? "OPEN" : "CLOSED");
}

// ═══════════════════════════════════════════════════════════
// FIREBASE — READ & EXECUTE COMMANDS
// ═══════════════════════════════════════════════════════════

void readAndExecuteCommands() {

  // Honey collection: true = open door + smoke, false = close door.
  if (Firebase.RTDB.getBool(&fbdo, "/commands/collect_honey")) {
    bool val = fbdo.boolData();
    if (val && !lastCollectHoney) {
      lastCollectHoney = true;
      collectHoney();
    } else if (!val && lastCollectHoney) {
      lastCollectHoney = false;
      stopHoneyCollection();
    }
  }

  // Feeding: app writes a volume in ml; run once, then ESP resets it to 0.
  if (Firebase.RTDB.getInt(&fbdo, "/commands/feed_ml")) {
    int ml = fbdo.intData();
    if (ml > 0) {
      feedBees(ml);
    }
  }

  // Entrance open / narrow (hornet screen buttons).
  if (Firebase.RTDB.getString(&fbdo, "/commands/entrance")) {
    String val = fbdo.stringData();
    if (val != entranceState) {
      if (val == "narrow") {
        narrowEntrance();
      } else {
        openEntrance();
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════
// RFID — ANY CARD TOGGLES THE HIVE LOCK (GPIO19)
// ═══════════════════════════════════════════════════════════

void checkRFID() {
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) return;

  String cardUID = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) cardUID += "0";
    cardUID += String(rfid.uid.uidByte[i], HEX);
    if (i < rfid.uid.size - 1) cardUID += " ";
  }
  cardUID.toUpperCase();
  Serial.printf("[RFID] Card: %s\n", cardUID.c_str());

  String timeStr = uptimeStamp();

  // Any card is accepted -> toggle the lock.
  if (lockState) {
    unlockHive();   // was locked -> unlock
  } else {
    lockHive();     // was unlocked -> lock
  }

  // Mirror to /security for the app's Security screen.
  Firebase.RTDB.setString(&fbdo, "/security/rfid_status", "granted");
  Firebase.RTDB.setString(&fbdo, "/security/last_card",   cardUID);
  Firebase.RTDB.setString(&fbdo, "/security/last_time",   timeStr);

  // Append to the access history log.
  String logPath = "/rfid_logs/log_" + String(millis());
  Firebase.RTDB.setString(&fbdo, logPath + "/card_id",   cardUID);
  Firebase.RTDB.setString(&fbdo, logPath + "/access",    "granted");
  Firebase.RTDB.setString(&fbdo, logPath + "/timestamp", timeStr);

  // Notify the app.
  pushAlert("rfid", lockState ? "Hive locked via RFID card."
                              : "Hive unlocked via RFID card.");

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

// ═══════════════════════════════════════════════════════════
// AUTOMATIC ALERTS + HORNET RESPONSE
// ═══════════════════════════════════════════════════════════

void checkAndSendAlerts() {
  if (receivedTemp > 36.0) {
    pushAlert("temperature", "High temp: " + String(receivedTemp) + "C");
  }
  if (receivedSound == "Swarming") {
    pushAlert("sound", "Swarming detected! Colony may leave.");
  }
  if (receivedSound == "Queen Loss") {
    pushAlert("sound", "Queen loss detected! Check hive immediately.");
  }
}

// React to a hornet only on the rising edge (false -> true) so we narrow
// once per event instead of every 30 s.
void handleHornet() {
  if (hornetDetected && !lastHornetState) {
    Serial.println("[HORNET] Detected — narrowing entrance");
    narrowEntrance();
    pushAlert("hornet", "Hornet detected! Entrance narrowed automatically.");
    Firebase.RTDB.setString(&fbdo, "/hornet_detection/last_detection", uptimeStamp());
  }
  lastHornetState = hornetDetected;
}

// ═══════════════════════════════════════════════════════════
// ESP-NOW CALLBACK  (keep it light: just store values)
// ═══════════════════════════════════════════════════════════

void onDataReceived(const uint8_t* mac, const uint8_t* data, int len) {
  if (len == sizeof(SensorData)) {
    memcpy(&incomingSensor, data, sizeof(SensorData));
    receivedTemp       = incomingSensor.temperature;
    receivedHumidity   = incomingSensor.humidity;
    receivedSound      = String(incomingSensor.soundResult);
    receivedConfidence = incomingSensor.confidence;
  } else if (len == sizeof(CamData)) {
    memcpy(&incomingCam, data, sizeof(CamData));
    hornetDetected = incomingCam.hornetDetected; // acted on in handleHornet()
  }
}

// ═══════════════════════════════════════════════════════════
// SETUP
// ═══════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);

  // ── SAFE INITIAL STATE ──────────────────────────────────
  // Pumps are ACTIVE LOW: drive the latch HIGH (=OFF) BEFORE switching the pin
  // to OUTPUT so the relay never sees a brief LOW glitch at boot.
  digitalWrite(RELAY_FEED_PIN,  HIGH);
  digitalWrite(RELAY_SMOKE_PIN, HIGH);
  pinMode(RELAY_FEED_PIN,  OUTPUT);
  pinMode(RELAY_SMOKE_PIN, OUTPUT);
  digitalWrite(RELAY_FEED_PIN,  HIGH); // OFF
  digitalWrite(RELAY_SMOKE_PIN, HIGH); // OFF

  // Ultrasonic trigger: plain output, held LOW.
  pinMode(TRIG_PIN, OUTPUT);
  digitalWrite(TRIG_PIN, LOW);
  pinMode(ECHO_PIN, INPUT);

  // Servos: attach and immediately drive to a known home position so they
  // don't jump to a random angle on power-up.
  servoDoor.attach(SERVO_DOOR_PIN);
  servoLock.attach(SERVO_LOCK_PIN);
  servoEntrance.attach(SERVO_ENTRANCE_PIN);
  servoDoor.write(DOOR_CLOSED_ANGLE);       // door closed
  servoLock.write(LOCK_LOCKED_ANGLE);       // hive LOCKED
  servoEntrance.write(ENTRANCE_OPEN_ANGLE); // entrance open
  doorOpen      = false;
  lockState     = true;
  entranceState = "open";

  // HX711
  scale.begin(HX711_DT, HX711_SCK);
  scale.set_scale(SCALE_CALIBRATION_FACTOR);
  scale.tare();
  Serial.println("[HX711] Scale ready");

  // RFID (SPI: SCK=14, MISO=27, MOSI=25, SS=5)
  SPI.begin(14, 27, 25, 5);
  rfid.PCD_Init();
  Serial.println("[RFID] Ready");

  // WiFi
  WiFi.mode(WIFI_AP_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WiFi] Connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n[WiFi] Connected: " + WiFi.localIP().toString());
  Serial.println("[ESP-NOW] MAC: " + WiFi.macAddress());

  // ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("[ESP-NOW] Init failed!");
    return;
  }
  esp_now_register_recv_cb(onDataReceived);
  Serial.println("[ESP-NOW] Ready");

  // Firebase
  config.api_key      = API_KEY;
  config.database_url = DATABASE_URL;
  config.cert.data    = nullptr;
  config.cert.file    = "";
  Firebase.signUp(&config, &auth, "", "");
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  fbdo.setResponseSize(4096);
  config.timeout.serverResponse = 10 * 1000;
  Serial.println("[Firebase] Connected");

  // Publish a clean initial state so the app reflects reality on first launch.
  Firebase.RTDB.setBool(&fbdo,   "/commands/collect_honey", false);
  Firebase.RTDB.setInt(&fbdo,    "/commands/feed_ml",       0);
  Firebase.RTDB.setBool(&fbdo,   "/commands/smoke_pump",    false);
  Firebase.RTDB.setBool(&fbdo,   "/commands/pump",          false);
  Firebase.RTDB.setString(&fbdo, "/commands/entrance",      "open");
  Firebase.RTDB.setBool(&fbdo,   "/hive_status/door_open",  false);
  Firebase.RTDB.setBool(&fbdo,   "/security/locked",        true);
  Firebase.RTDB.setString(&fbdo, "/security/rfid_status",   "Waiting for Card");
  Serial.println("[Firebase] Initial state published");
}

// ═══════════════════════════════════════════════════════════
// LOOP
// ═══════════════════════════════════════════════════════════

void loop() {
  if (!Firebase.ready()) return;

  unsigned long now = millis();
  if (now - lastSensorUpload >= UPLOAD_INTERVAL) {
    lastSensorUpload = now;
    uploadSensorData();
    checkAndSendAlerts();
  }

  handleHornet();
  readAndExecuteCommands();
  checkRFID();

  delay(200);
}
