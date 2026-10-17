FROM debian:bookworm
# Validation container for the Ollama Backup Deluxe devcontainer kit.
# The kit's restore is fully offline; this image just needs bash + tar (built in)
# and optionally curl for the host-reachability check.
RUN apt-get update -qq && apt-get install -y -qq curl xz-utils ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /kit
CMD ["bash"]
