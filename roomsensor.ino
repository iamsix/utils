#include "DHT.h"
#include <WiFi.h>
#include <WiFiUdp.h>
#include <SNMP_Agent.h>
#include <Arduino.h>
#include "MH-Z14A.h"
#include "credentials.h"
// #include <ArduinoOTA.h>

#define DHTPIN 4     // Digital pin connected to the DHT sensor
#define DHTTYPE DHT11   // DHT 11

const char* ssid     = WIFI_SSID;
const char* password = WIFI_PASSWD;

int temp_c = 0;
int hum = 0;
int ppm = -1;

DHT dht(DHTPIN, DHTTYPE);
WiFiUDP udp;
SNMPAgent snmp("public");
MHZ14A co2;

void setup() {
  Serial.begin(115200);
  Serial.println(F("Serial works"));
  // put your setup code here, to run once:
  dht.begin();

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("");
  Serial.println("WiFi connected.");
  Serial.println("IP address: ");
  Serial.println(WiFi.localIP());

  snmp.setUDP(&udp);

  snmp.addIntegerHandler(".1.3.6.1.4.1.5.1", &temp_c);
  snmp.addIntegerHandler(".1.3.6.1.4.1.5.2", &hum);
  snmp.addIntegerHandler(".1.3.6.1.4.1.5.3", &ppm);
  snmp.sortHandlers();

  Serial2.begin(9600);
  co2.begin(Serial2, Serial, 4000);
  co2.setDebug(true);  
  



}

void loop() {
  float h = dht.readHumidity();
  float t = dht.readTemperature();

  temp_c = static_cast<int>(t*10);
  hum = static_cast<int>(h);
  // put your main code here, to run repeatedly:

  if (isnan(h) || isnan(t)) {
    Serial.println(F("Failed to read from DHT sensor!"));
    return;
  }
  Serial.print(F("Humidity: "));
  Serial.print(h);
  Serial.print(F("%  Temperature: "));
  Serial.println(t);

  Serial.print(temp_c);
  Serial.print(" - ");
  Serial.println(hum);

  ppm = co2.readConcentrationPPM(0x01);

  Serial.print("CO2: ");
  Serial.print(ppm);
  Serial.println(" ppm.");

  //delay(5000);



  uint32_t moment = millis();
  while (millis() - moment < 5000) {
    snmp.loop();
    delay(5);
    yield();
  }

}
