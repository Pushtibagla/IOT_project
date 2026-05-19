#include "esp_camera.h"
#include <WiFi.h>
#include <WebServer.h>
#include "img_converters.h"

#include <WiFiClientSecure.h>
#include <UniversalTelegramBot.h>

// OLED
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// WIFI
const char* ssid = "BBH_4";
const char* password = "Bbhindore#1";

// TELEGRAM
#define BOTtoken "8722114401:AAESv1cHuPbc4syUrRm9Pm2HhDNsTL-imSc"
#define CHAT_ID "5205187464"

WiFiClientSecure client;
UniversalTelegramBot bot(BOTtoken, client);

// LED
#define GREEN_LED 12
#define RED_LED 13

// BUTTON
#define BUTTON_PIN 2

// OLED
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// CAMERA PINS
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

WebServer server(80);

// ================= OLED =================
void oledPrint(const char* msg) {
  display.clearDisplay();

  display.setTextSize(1);
  display.setCursor(15, 0);
  display.println("SMART DOORBELL");

  display.drawLine(0, 10, 128, 10, WHITE);

  display.setTextSize(2);
  display.setCursor(10, 25);
  display.println(msg);

  display.display();
}

// ================= CAPTURE =================
void handle_capture() {
  camera_fb_t * fb = esp_camera_fb_get();
  if (!fb) {
    server.send(500, "text/plain", "Camera capture failed");
    return;
  }

  uint8_t * bmp_buf = NULL;
  size_t bmp_len = 0;

  if (!frame2bmp(fb, &bmp_buf, &bmp_len)) {
    server.send(500, "text/plain", "BMP conversion failed");
    esp_camera_fb_return(fb);
    return;
  }

  server.sendHeader("Content-Type", "image/bmp");
  server.send_P(200, "image/bmp", (const char *)bmp_buf, bmp_len);

  free(bmp_buf);
  esp_camera_fb_return(fb);
}

// ================= WEB =================
void handle_root() {
  static const char html[] PROGMEM = R"rawliteral(
  <html><body>
  <h2>ESP32-CAM Live</h2>
  <img id='cam' src='/capture' width='320'><br>
  <script>
  setInterval(function(){
    document.getElementById('cam').src = '/capture?t=' + new Date().getTime();
  },2000);
  </script>
  </body></html>)rawliteral";

  server.send(200, "text/html", html);
}

// ================= TELEGRAM =================
void sendPhotoTelegram() {
  String url = "http://" + WiFi.localIP().toString() + "/capture";
  bot.sendMessage(CHAT_ID, "Visitor:\n" + url, "");

  oledPrint("Visitor");
}

// ================= TELEGRAM =================
void handleTelegram() {
  int numNewMessages = bot.getUpdates(bot.last_message_received + 1);

  for (int i = 0; i < numNewMessages; i++) {
    String text = bot.messages[i].text;

    if (text == "/capture") {
      sendPhotoTelegram();
    }
    else if (text == "/open") {
      digitalWrite(GREEN_LED, HIGH);
      digitalWrite(RED_LED, LOW);

      bot.sendMessage(CHAT_ID, "Door Opened (10 sec)", "");
      oledPrint("Opened");

      delay(10000);

      digitalWrite(GREEN_LED, LOW);
      digitalWrite(RED_LED, HIGH);

      bot.sendMessage(CHAT_ID, "Door Closed", "");
      oledPrint("Closed");
    }
    else if (text == "/deny") {
      digitalWrite(GREEN_LED, LOW);
      digitalWrite(RED_LED, HIGH);

      bot.sendMessage(CHAT_ID, "Access Denied", "");
      oledPrint("Denied");
    }
  }
}

// ================= SERIAL =================
void handleSerialTrigger() {
  if (Serial.available()) {
    if (Serial.read() == 'c') {
      Serial.println("Capture triggered");
      sendPhotoTelegram();
    }
  }
}

// ================= BUTTON =================
void handleButtonPress() {
  static bool lastState = HIGH;
  bool currentState = digitalRead(BUTTON_PIN);

  if (lastState == HIGH && currentState == LOW) {
    Serial.println("Doorbell Pressed");
    sendPhotoTelegram();
    delay(250);
  }

  lastState = currentState;
}

void setup() {
  Serial.begin(115200);

  pinMode(GREEN_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  digitalWrite(GREEN_LED, LOW);
  digitalWrite(RED_LED, HIGH);

  Wire.begin(14, 15);

  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED failed");
  }

  display.setTextColor(WHITE);

  oledPrint("Booting");

  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;

  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;

  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;

  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;

  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;

  config.xclk_freq_hz = 20000000;

  config.pixel_format = PIXFORMAT_RGB565;
  config.frame_size = FRAMESIZE_QQVGA;
  config.fb_count = 1;

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("Camera init failed");
    oledPrint("Cam Fail");
    return;
  }

  oledPrint("Cam Ready");

  WiFi.begin(ssid, password);

  oledPrint("Connecting");

  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print(".");
  }

  oledPrint("WiFi OK");

  client.setInsecure();
  bot.sendMessage(CHAT_ID, "System Ready", "");

  oledPrint("Ready");

  server.on("/", handle_root);
  server.on("/capture", handle_capture);
  server.begin();

  Serial.println("Server started");
}

void loop() {
  server.handleClient();
  handleTelegram();
  handleSerialTrigger();
  handleButtonPress();
}
