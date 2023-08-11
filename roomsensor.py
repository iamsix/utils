from snmp import Engine, SNMPv2c
import plotly.graph_objects as go
from nicegui import ui, app
import pandas as pd
from datetime import datetime
import sqlite3

con = sqlite3.connect("tempdata.sqlite")
c = con.cursor()
q = '''CREATE TABLE IF NOT EXISTS 'data' ("timestamp" integer, "temp" float, "humidity" integer, "co2" integer);'''
c.execute(q)
con.commit()

current = {"temp": 0.0, "humidity": 0, "co2": 0}

async def read_sensors():
    temp, hum, co2 = None, None, None
    try:
        with Engine(SNMPv2c, defaultCommunity="public".encode()) as engine:
            host = engine.Manager("192.168.1.117")
            response = host.get(
                "1.3.6.1.4.1.5.1", 
                "1.3.6.1.4.1.5.2", 
                "1.3.6.1.4.1.5.3", 
                timeout=1.0)
            temp = response.variableBindings[0].value.value / 10
            hum = response.variableBindings[1].value.value
            co2 = response.variableBindings[2].value.value
            current['temp'] = temp
            current['humidity'] = hum
            current['co2'] = co2
    except Exception as e:
        pass

    if temp and hum and co2:
        ts = datetime.now().isoformat()
        q = "INSERT INTO data VALUES (?, ?, ?, ?);"
        c.execute(q, (ts, temp, hum, co2))
        con.commit()
    #    return {"temp": temp, "humidity": hum, "co2": co2}


ui.timer(30.0, read_sensors)

@ui.refreshable
def graph():
    df = pd.read_sql_query("SELECT * from data", con)
    fig = go.Figure([go.Scatter(x=df['timestamp'], 
        y=df['temp'], 
        name="Temperature", 
        hovertemplate='%{y:.1f}°C<br>%{x}',
        yaxis='y1')])
    fig.add_scatter(x=df['timestamp'], 
        y=df['humidity'], 
        name="Humidity",
        hovertemplate="%{y}%<br>%{x}",
        yaxis='y1')
    fig.add_scatter(x=df['timestamp'], 
        y=df['co2'], 
        name="CO2 PPM", 
        hovertemplate="%{y} PPM<br>%{x}",
        yaxis='y2')
    fig.update_layout(
        margin=dict(l=20, r=0, t=40, b=0),
        title_text="Bedroom",
        yaxis=dict(title="Temp + Humidity"),
        yaxis2=dict(title="CO2", overlaying='y', side='right'),
#        yaxis3=dict(title="Humidity", overlaying='y', side='left'),
#        plot_bgcolor='white',
        paper_bgcolor='rgba(0,0,0,0)',
        font_color="#ccc",
    )

    ui.plotly(fig).classes('w-full h-100')
    ui.label("Current data:")
    ui.label(f"{current['temp']}°C - {current['humidity']}% Humidity - {current['co2']} PPM CO2")

graph()
ui.run(port=5656, title="Temperature graph", show=False, dark=True)
app.on_connect(graph.refresh)
