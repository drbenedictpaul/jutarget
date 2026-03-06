# Use the official Julia 1.10 image
FROM julia:1.10

# 1. Install System Tools & an available version of Java for SnpEff
RUN apt-get update && apt-get install -y \
    minimap2 \
    samtools \
    bcftools \
    openjdk-21-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# 2. Set Working Directory
WORKDIR /app

# 3. Copy SnpEff into the image
COPY bin /app/bin

# 4. Copy Project Definitions first (for caching)
COPY Project.toml Manifest.toml ./

# 5. Install Julia Packages
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# 6. Copy Application Source Code
COPY . .

# 7. Overwrite local config with the Docker config
COPY config_docker.toml config.toml

# 8. Create data directories inside the container
RUN mkdir -p /root/juTarget_input /root/juTarget_output /root/juTarget_results

# 9. Expose the Web Port
EXPOSE 8001

# 10. Start the Server
CMD ["julia", "--project=.", "juTarget_web.jl"]

