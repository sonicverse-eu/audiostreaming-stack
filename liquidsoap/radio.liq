# ============================================================
# Breeze Radio — Liquidsoap Configuration
# ============================================================

# --- Settings ---
settings.harbor.bind_addrs.set(["0.0.0.0"])
settings.log.level.set(3)

harbor_password = environment.get("HARBOR_PASSWORD", "changeme")
icecast_pass = environment.get("ICECAST_SOURCE_PASSWORD", "changeme")
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
emergency = single("/emergency-audio/fallback.mp3")

# --- Fallback chain ---
# Priority: primary FLAC > secondary Ogg > emergency file
radio = fallback(
  track_sensitive=false,
  [primary, secondary, emergency]
)

# --- Silence detection + Pushover alerts ---
silence_threshold = float_of_string(environment.get("SILENCE_THRESHOLD_DB", "-40"))
silence_duration = float_of_string(environment.get("SILENCE_DURATION", "15"))

radio = blank.detect(
  radio,
  max_blank=silence_duration,
  threshold=silence_threshold,
  on_blank=fun () -> begin
    log("ALERT: Silence detected for #{silence_duration}s (threshold: #{silence_threshold}dB)")
    ignore(process.run("wget -q -O /dev/null 'http://analytics:8888/alert?type=silence_start'"))
  end,
  on_noise=fun () -> begin
    log("OK: Audio resumed after silence")
    ignore(process.run("wget -q -O /dev/null 'http://analytics:8888/alert?type=silence_end'"))
  end
)

# --- Icecast outputs (multiple bitrates/formats) ---

output.icecast(
  %mp3(bitrate=128, samplerate=44100, stereo=true),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-mp3-128",
  name="Breeze Radio - MP3 128k",
  description="Breeze Radio Nederland",
  radio
)

output.icecast(
  %mp3(bitrate=320, samplerate=44100, stereo=true),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-mp3-320",
  name="Breeze Radio - MP3 320k",
  description="Breeze Radio Nederland",
  radio
)

output.icecast(
  %fdkaac(bitrate=128, channels=2, samplerate=44100),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-aac-128",
  name="Breeze Radio - AAC 128k",
  description="Breeze Radio Nederland",
  radio
)

output.icecast(
  %vorbis(bitrate=128, channels=2, samplerate=44100),
  host=icecast_host, port=icecast_port,
  password=icecast_pass,
  mount="/stream-ogg-128",
  name="Breeze Radio - Ogg 128k",
  description="Breeze Radio Nederland",
  radio
)

# --- HLS output (for mobile streaming) ---
output.file.hls(
  "/hls",
  segment_duration=6.0,
  segments=5,
  segments_overhead=10,
  playlist="live.m3u8",
  [
    ("aac_128",
      %ffmpeg(format="mpegts",
        %audio(codec="aac", b="128k", channels=2, ar=44100)
      )
    ),
    ("mp3_128",
      %ffmpeg(format="mpegts",
        %audio(codec="libmp3lame", b="128k", channels=2, ar=44100)
      )
    )
  ],
  radio
)
