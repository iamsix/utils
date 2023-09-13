#include <WiFi.h>
// #include <WiFiUdp.h>
#include <HTTPClient.h>
#include <ArduinoOTA.h>
#include "credentials.h"

// const char *ssid = "ssid"
// const char *password = "password
// #define discord_webhook "https://discord.com/api/webhooks/.."

const char *discordappCertificate =
    "-----BEGIN CERTIFICATE-----\n"
    "MIIDzTCCArWgAwIBAgIQCjeHZF5ftIwiTv0b7RQMPDANBgkqhkiG9w0BAQsFADBa\n"
    "MQswCQYDVQQGEwJJRTESMBAGA1UEChMJQmFsdGltb3JlMRMwEQYDVQQLEwpDeWJl\n"
    "clRydXN0MSIwIAYDVQQDExlCYWx0aW1vcmUgQ3liZXJUcnVzdCBSb290MB4XDTIw\n"
    "MDEyNzEyNDgwOFoXDTI0MTIzMTIzNTk1OVowSjELMAkGA1UEBhMCVVMxGTAXBgNV\n"
    "BAoTEENsb3VkZmxhcmUsIEluYy4xIDAeBgNVBAMTF0Nsb3VkZmxhcmUgSW5jIEVD\n"
    "QyBDQS0zMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEua1NZpkUC0bsH4HRKlAe\n"
    "nQMVLzQSfS2WuIg4m4Vfj7+7Te9hRsTJc9QkT+DuHM5ss1FxL2ruTAUJd9NyYqSb\n"
    "16OCAWgwggFkMB0GA1UdDgQWBBSlzjfq67B1DpRniLRF+tkkEIeWHzAfBgNVHSME\n"
    "GDAWgBTlnVkwgkdYzKz6CFQ2hns6tQRN8DAOBgNVHQ8BAf8EBAMCAYYwHQYDVR0l\n"
    "BBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMBIGA1UdEwEB/wQIMAYBAf8CAQAwNAYI\n"
    "KwYBBQUHAQEEKDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5j\n"
    "b20wOgYDVR0fBDMwMTAvoC2gK4YpaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL09t\n"
    "bmlyb290MjAyNS5jcmwwbQYDVR0gBGYwZDA3BglghkgBhv1sAQEwKjAoBggrBgEF\n"
    "BQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzALBglghkgBhv1sAQIw\n"
    "CAYGZ4EMAQIBMAgGBmeBDAECAjAIBgZngQwBAgMwDQYJKoZIhvcNAQELBQADggEB\n"
    "AAUkHd0bsCrrmNaF4zlNXmtXnYJX/OvoMaJXkGUFvhZEOFp3ArnPEELG4ZKk40Un\n"
    "+ABHLGioVplTVI+tnkDB0A+21w0LOEhsUCxJkAZbZB2LzEgwLt4I4ptJIsCSDBFe\n"
    "lpKU1fwg3FZs5ZKTv3ocwDfjhUkV+ivhdDkYD7fa86JXWGBPzI6UAPxGezQxPk1H\n"
    "goE6y/SJXQ7vTQ1unBuCJN0yJV0ReFEQPaA1IwQvZW+cwdFD19Ae8zFnWSfda9J1\n"
    "CZMRJCQUzym+5iPDuI9yP+kHyCREU3qzuWFloUwOxkgAyXVjBYdwRVKD05WdRerw\n"
    "6DEdfgkfCv4+3ao8XnTSrLE=\n"
    "-----END CERTIFICATE-----\n";


const int LightDarkThreshold = 500;

struct lightSensor
{
  int sensorValue;
  int sensorPin;
  bool on;
  char name[20];
};

lightSensor dryer1 = {0, 36, false, "Dryer Heavy"};
lightSensor dryer2 = {0, 39, false, "Dryer Press"};
lightSensor dryer3 = {0, 34, false, "Dryer Delicate"};

lightSensor washer1 = {0, 35, false, "Washer Rinse"};
lightSensor washer2 = {0, 32, false, "Washer Softener"};
lightSensor washer3 = {0, 33, false, "Washer Spin"};

lightSensor lightSensors[6] = {dryer1, dryer2, dryer3, washer1, washer2, washer3};


void setup()
{

  Serial.begin(115200);
  // pinMode(2, OUTPUT); // set the LED pin mode

  delay(10);

  // We start by connecting to a WiFi network

  Serial.println();
  Serial.println();
  Serial.print("Connecting to ");
  Serial.println(ssid);

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED)
  {
    delay(500);
    Serial.print(".");
  }

  Serial.println("");
  Serial.println("WiFi connected.");
  Serial.println("IP address: ");
  Serial.println(WiFi.localIP());


  ArduinoOTA
      .onStart([]()
               {
      String type;
      if (ArduinoOTA.getCommand() == U_FLASH)
        type = "sketch";
      else // U_SPIFFS
        type = "filesystem";

      // NOTE: if updating SPIFFS this would be the place to unmount SPIFFS using SPIFFS.end()
      Serial.println("Start updating " + type); })
      .onEnd([]()
             { Serial.println("\nEnd"); })
      .onProgress([](unsigned int progress, unsigned int total)
                  { Serial.printf("Progress: %u%%\r", (progress / (total / 100))); })
      .onError([](ota_error_t error)
               {
      Serial.printf("Error[%u]: ", error);
      if (error == OTA_AUTH_ERROR) Serial.println("Auth Failed");
      else if (error == OTA_BEGIN_ERROR) Serial.println("Begin Failed");
      else if (error == OTA_CONNECT_ERROR) Serial.println("Connect Failed");
      else if (error == OTA_RECEIVE_ERROR) Serial.println("Receive Failed");
      else if (error == OTA_END_ERROR) Serial.println("End Failed"); });

  ArduinoOTA.begin();
}

void send_discord(String content)
{
  WiFiClientSecure *client2 = new WiFiClientSecure;
  // String content = "TEST";
  client2->setCACert(discordappCertificate);
  {
    HTTPClient https;
    Serial.println("[HTTP] Connecting to Discord...");
    Serial.println("[HTTP] Message: " + content);
    if (https.begin(*client2, discord_webhook))
    { // HTTPS
      Serial.println("Connected to discord... sending data");
      https.addHeader("Content-Type", "application/json");
      int httpCode = https.POST("{\"content\":\"" + content + "\"}");

      // httpCode will be negative on error
      if (httpCode > 0)
      {
        // HTTP header has been send and Server response header has been handled
        Serial.print("[HTTP] Status code: ");
        Serial.println(httpCode);

        // file found at server
        if (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_MOVED_PERMANENTLY)
        {
          String payload = https.getString();
          Serial.print("[HTTP] Response: ");
          Serial.println(payload);
        }
      }
      else
      {
        Serial.print("[HTTP] Post... failed, error: ");
        Serial.println(https.errorToString(httpCode).c_str());
      }

      https.end();
    }
    else
    {
      Serial.printf("[HTTP] Unable to connect\n");
    }

    // End extra scoping block
  }

  delete client2;
}

void loop()
{
  // ArduinoOTA.handle();

  char buffer[200];
  int length = 0;
  for (int i = 0; i < 6; i++)
  {
    lightSensors[i].sensorValue = analogRead(lightSensors[i].sensorPin);
    length += sprintf(buffer + length, "%s: %d - ", lightSensors[i].name, lightSensors[i].sensorValue);
    if (lightSensors[i].on && lightSensors[i].sensorValue < LightDarkThreshold)
    {
      lightSensors[i].on = false;
      char discbuf[30];
      sprintf(discbuf, "%s turned off!", lightSensors[i].name);
      Serial.println(discbuf);

      send_discord(discbuf);
    }
    else if (!lightSensors[i].on && lightSensors[i].sensorValue > LightDarkThreshold)
    {
      lightSensors[i].on = true;
      char discbuf[30];
      sprintf(discbuf, "%s turned on!", lightSensors[i].name);
      Serial.println(discbuf);

      send_discord(discbuf);
    }
  }

  Serial.println(buffer);

  // delay(1000);

  // For the OTA it's better to do this:
  uint32_t moment = millis();
  while (millis() - moment < 1000)
  {
    ArduinoOTA.handle();
    delay(5);
    yield();
  }
}

// To be used for washer finish/dryer finish
// // https://github.com/ShaneMcC/beeps/blob/master/hedwigs-theme.sh
// void hedwig() {
//   int LENGTH=300;
//   tone(BUZZERPIN, 617, LENGTH);
//   tone(BUZZERPIN, 824, (LENGTH * 3/2));
//   tone(BUZZERPIN, 900, (LENGTH/2));
//   tone(BUZZERPIN, 837, LENGTH);
//   tone(BUZZERPIN, 824, (LENGTH * 2));

//   tone(BUZZERPIN, 1234, LENGTH);
//   tone(BUZZERPIN, 1100, (LENGTH * 5/2));
//   tone(BUZZERPIN, 925, (LENGTH * 5/2));
//   tone(BUZZERPIN, 824, (LENGTH * 3/2));
//   tone(BUZZERPIN, 980, (LENGTH/2));

//   tone(BUZZERPIN, 837, LENGTH);
//   tone(BUZZERPIN, 777, (LENGTH*2));
//   tone(BUZZERPIN, 837, LENGTH);
//   tone(BUZZERPIN, 617, (LENGTH* 5/2));
//   noTone(BUZZERPIN);

// }

// // beep -f987 -l53 -D53 -n -f987 -l53 -D53 -n -f987 -l53 -D53 -n -f987 -l428 -n -f784 -l428 -n -f880 -l428 -n -f987 -l107 -D214 -n -f880 -l107 -n -f987 -l857
// // https://www.hooktheory.com/theorytab/view/nobuo-uematsu/final-fantasy-vii---victory-fanfare
// void ff_victory() {
  
//   tone(BUZZERPIN, 784, 100); // c
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 784, 100); // c
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 784, 100); // c
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 784, 700); // c
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 622, 500); // g
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 698, 500); // a
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 784, 300); // b
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 698, 100); // a
//   noTone(BUZZERPIN);
//   delay(10);

//   tone(BUZZERPIN, 784, 800); // b
//   noTone(BUZZERPIN);
//   delay(10);

//   noTone(BUZZERPIN);
// }
