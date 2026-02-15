# Use the official Julia 1.10 image
FROM julia:1.10

# 1. Install System Tools (Minimap2, Samtools, Bcftools)
RUN apt-get update && apt-get install -y \
    minimap2 \
    samtools \
    bcftools \
    && rm -rf /var/lib/apt/lists/*

# 2. Set Working Directory
WORKDIR /app

# 3. Copy Project Definitions first (for caching)
COPY Project.toml Manifest.toml ./

# 4. Install Julia Packages
# We explicitly instantiate for the container environment
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# 5. Copy Application Source Code
COPY . .

# 6. Overwrite local config with the Docker config
COPY config_docker.toml config.toml

# 7. Remove the "Press Enter" interactive block for Docker automation
# This prevents the container from hanging waiting for keyboard input
RUN sed -i '/readline()/d' juTarget_web.jl

# 8. Create data directories inside the container
RUN mkdir -p /root/juTarget_input /root/juTarget_output /root/juTarget_results

# 9. Expose the Web Port
EXPOSE 8000

# 10. Start the Server
CMD ["julia", "--project=.", "juTarget_web.jl"]