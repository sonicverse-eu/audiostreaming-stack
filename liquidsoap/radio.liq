# ============================================================
# Liquidsoap Configuration
# ============================================================

# --- Settings ---
settings.harbor.bind_addrs.set(["0.0.0.0"])
settings.log.level.set(3)

station_name = environment.get(default="Radio Station", "STATION_NAME")
harbor_password = environment.get(default="changeme", "HARBOR_PASSWORD")
icecast_pass = environment.get(default="changeme", "ICECAST_SOURCE_PASSWORD")
icecast_host = "icecast"
icecast_port = 8000

# --- Inputs from studio ---

# Primary: lossless FLAC stream
primary = input.harbor(
  "primary",
  port=8010,
  password=harbor_password,
  max=30.0,
  buffer=5.0
)

# Fallback: lower bitrate Ogg stream
secondary = input.harbor(
  "secondary",
  port=8011,
  password=harbor_password,
  max=30.0,
  buffer=5.0
)

# --- Emergency fallback ---
# Use emergency file if available, otherwise output silence
emergency =
  if file.exists("/emergency-audio/fallback.mp3") then
    single("/emergency-audio/fallback.mp3")
  else
    log("No emergency audio file found, using silence as last resort")
    blank()
  end

# --- Fallback chain ---
# Priority: primary FLAC > secondary Ogg > emergency file/silence
radio = fallback(
  track_sensitive=false,
  [primary, secondary, emergency]
)

# --- Silence detection + Pushover alerts ---
silence_threshold = float_of_string(environment.get(default="-40", "SILENCE_THRESHOLD_DB"))
silence_duration = float_of_string(environment.get(default="15", "SILENCE_DURATION"))

radio = blank.detect(
  radio,
  max_blank=silence_duration,
  threshold=silence_threshold
)

radio.on_blank(synchronous=false, fun () -> begin
  log("ALERT: Silence detected for #{silence_duration}s (threshold: #{silence_threshold}dB)")
  ignore(process.run("wget -q -O /dev/null 'http://analytics:8888/alert?type=silence_start'"))
end)

radio.on_noise(synchronous=false, fun () -> begin
  log("OK: Audio resumed after silence")
  ignore(process.run("wget -q -O /dev/null 'http://analytics:8888/alert?type=silence_end'"))
end)

# --- Icecast outputs (multiple bitrates/formats) ---

output.icecast(
  %mp3(bitrate=128, samplerate=44100, stereo=true),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-mp3-128",
  name="#{station_name} - MP3 128k",
  description=station_name,
  radio
)

output.icecast(
  %mp3(bitrate=192, samplerate=44100, stereo=true),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-mp3-192",
  name="#{station_name} - MP3 192k",
  description=station_name,
  radio
)

output.icecast(
  %mp3(bitrate=320, samplerate=44100, stereo=true),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-mp3-320",
  name="#{station_name} - MP3 320k",
  description=station_name,
  radio
)

output.icecast(
  %fdkaac(bitrate=128, channels=2, samplerate=44100),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-aac-128",
  name="#{station_name} - AAC 128k",
  description=station_name,
  radio
)

output.icecast(
  %fdkaac(bitrate=192, channels=2, samplerate=44100),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-aac-192",
  name="#{station_name} - AAC 192k",
  description=station_name,
  radio
)

output.icecast(
  %vorbis.cbr(bitrate=128, channels=2, samplerate=44100),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-ogg-128",
  name="#{station_name} - Ogg 128k",
  description=station_name,
  radio
)

output.icecast(
  %ogg(%flac(channels=2, bits_per_sample=16, samplerate=44100)),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-flac",
  name="#{station_name} - FLAC HiFi",
  description=station_name,
  radio
)

# --- HLS output (adaptive bitrate streaming) ---
output.file.hls(
  "/hls",
  segment_duration=4.0,
  segments=6,
  segments_overhead=12,
  playlist="live.m3u8",
  [
    # Low — mobile on poor connections
    ("aac_48",
      %ffmpeg(format="mpegts",
        %audio(codec="aac", b="48k", channels=2, ar=44100, profile="aac_he")
      )
    ),
    # Medium — mobile on decent connections
    ("aac_96",
      %ffmpeg(format="mpegts",
        %audio(codec="aac", b="96k", channels=2, ar=44100)
      )
    ),
    # Standard — wifi / good mobile
    ("aac_128",
      %ffmpeg(format="mpegts",
        %audio(codec="aac", b="128k", channels=2, ar=44100)
      )
    ),
    # High quality — wifi / broadband
    ("aac_256",
      %ffmpeg(format="mpegts",
        %audio(codec="aac", b="256k", channels=2, ar=44100)
      )
    )
  ],
  radio
)
