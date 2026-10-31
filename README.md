# Torpet

A macOS menu bar app that shows the outdoor and indoor temperature from the Netatmo weather station at our
summer cottage ("torpet" in Swedish), for example `Ute 4,2°  Inne 12,5°` (outdoor / indoor). Click it to see:

- **Overview**: outdoor and indoor temperature with trend and today's min/max.
- **Every value** per module: temperature, humidity, CO₂, noise, pressure with trend, wind and gusts with
  direction, rain (last 5 min, last hour, today), battery, signal strength and time of measurement. Values the
  app doesn't recognize are shown too, under Netatmo's own names.
- **History** from Netatmo's `getmeasure`, charted per module and measurement over a day, week, month or year.
  For month and year, temperature is shown as the daily min–max range. Rain is shown as bars, wind together
  with gusts.

<p align="center"><img src="docs/screenshot.png" width="440" alt="Torpet: the popover with all values and history"></p>

<sub>The screenshot is rendered from the sample data in `Samples/getstationsdata.json`.</sub>

The app is available in Swedish and English; pick the language under settings (the gear icon). Numbers, dates
and compass directions follow the chosen language.

Data is fetched every ten minutes, which is how often the station reports. It's also fetched when you open the
popover, if the last fetch is more than two minutes old.

## Build and install

```bash
./build.sh            # builds build/Torpet.app
./build.sh install    # copies it to ~/Applications and launches it
```

Requires macOS 14 or later and Xcode or the Command Line Tools. Launch at login is in the settings.

## Netatmo credentials

The app fetches data the same way as [hammarbynext](https://github.com/jonelf/hammarbynext)
(`NetatmoSource.java`): OAuth with a refresh token against `api.netatmo.com`, then `getstationsdata`.

1. Go to <https://dev.netatmo.com/apps/> and open your app (an existing app works fine).
2. Copy the **client ID** and **client secret**.
3. Under **Token generator**, select the `read_station` scope and generate a token. Copy the **refresh token**.
4. Paste all three into the app's settings and click Save.

**Use a refresh token of its own for this app.** Netatmo issues a new refresh token on every renewal, so if two
clients share a token, one of them gets locked out. The app saves the new token each time, in
`~/Library/Application Support/Torpet/netatmo.json` (readable only by you). It always re-reads that file before
renewing, so two processes on the same Mac can't lock each other out. If Netatmo still rejects the token, the
app says so; generate a new one and paste it in.

## Files

| File | Contents |
|---|---|
| `Sources/Torpet/Netatmo.swift` | API client, token renewal, parsing of `getstationsdata` and `getmeasure` |
| `Sources/Torpet/Format.swift` | Labels and units for every value |
| `Sources/Torpet/Language.swift` | The language setting (Swedish or English) |
| `Sources/Torpet/WeatherStore.swift` | Periodic fetching, cached history, the menu bar text |
| `Sources/Torpet/Views.swift` | The popover: overview, modules, chart, settings |
| `Samples/getstationsdata.json` | Sample response for checking the layout without Netatmo |

To render the popover with sample data to an image, without calling Netatmo (debug builds only):

```bash
swift run Torpet --snapshot docs/screenshot.png Samples/getstationsdata.json -language en
```
