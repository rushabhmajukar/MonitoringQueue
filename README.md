The PowerShell script monitors the build queue to determine if any agents are being utilized by the build pipelines. If no builds are queued, the script shuts down all online agents except one, which remains available at all times. Conversely, if builds are queued and agents are offline, the script brings the necessary agents online.
Yaml pipeline triggers every hour to run the PowerShell script.
