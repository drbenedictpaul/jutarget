module juTarget

using Genie, Logging, TOML, DataFrames, CSV, Dates

export process_sample

# --- EXTERNAL TOOL WRAPPERS ---

function run_minimap2(config::Dict, sample_name::String, fastq_path::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting Minimap2 Alignment...")
    ref = config["paths"]["reference_genome"]
    exe = config["paths"]["minimap2"]
    sam_out = joinpath(output_dir, "$sample_name.sam")
    
    # -ax map-ont: Preset for Oxford Nanopore reads
    cmd = `$exe -ax map-ont -t 4 $ref $fastq_path`
    try
        run(pipeline(cmd, stdout=sam_out, stderr=log_io))
        return true
    catch e
        println(log_io, "Error in minimap2: $e")
        return false
    end
end

function run_samtools_sort(config::Dict, sample_name::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting SAM to Sorted BAM conversion...")
    exe = config["paths"]["samtools"]
    sam_in = joinpath(output_dir, "$sample_name.sam")
    bam_out = joinpath(output_dir, "$sample_name.sorted.bam")
    
    cmd_view = `$exe view -bS $sam_in`
    cmd_sort = `$exe sort -o $bam_out -`
    
    try
        # Pipe view -> sort
        run(pipeline(cmd_view, cmd_sort, stderr=log_io))
        rm(sam_in, force=true) # Cleanup SAM to save space
        return true
    catch e
        println(log_io, "Error in samtools sort: $e")
        return false
    end
end

function run_bcftools_call(config::Dict, sample_name::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting Variant Calling (bcftools)...")
    exe = config["paths"]["bcftools"]
    ref = config["paths"]["reference_genome"]
    bam_in = joinpath(output_dir, "$sample_name.sorted.bam")
    vcf_out = joinpath(output_dir, "$sample_name.vcf")
    
    # mpileup -> call
    cmd_pileup = `$exe mpileup -Ou -f $ref $bam_in`
    cmd_call = `$exe call -mv -o $vcf_out`
    
    try
        run(pipeline(cmd_pileup, cmd_call, stderr=log_io))
        return true
    catch e
        println(log_io, "Error in bcftools call: $e")
        return false
    end
end

# --- ORCHESTRATION ---

function process_sample(config::Dict, sample_name::String, fastq_path::String, output_dir_base::String, channel, log_io::IO)
    sample_out_dir = joinpath(output_dir_base, sample_name)
    mkpath(sample_out_dir)

    try
        # 1. Alignment
        update_status(channel, sample_name, "Aligning (Minimap2)", 10)
        if !run_minimap2(config, sample_name, fastq_path, sample_out_dir, log_io)
            error("Minimap2 failed")
        end

        # 2. Sorting
        update_status(channel, sample_name, "Sorting (Samtools)", 40)
        if !run_samtools_sort(config, sample_name, sample_out_dir, log_io)
            error("Samtools sort failed")
        end

        # 3. Variant Calling
        update_status(channel, sample_name, "Calling Variants (Bcftools)", 70)
        if !run_bcftools_call(config, sample_name, sample_out_dir, log_io)
            error("Bcftools call failed")
        end

        update_status(channel, sample_name, "Completed", 100)

    catch e
        println(log_io, "FATAL ERROR: $e")
        update_status(channel, sample_name, "Failed", 0)
        rethrow(e)
    end
end

function update_status(channel, sample, status, progress)
    if channel !== nothing
        put!(channel, Dict(:sample => sample, :status => status, :progress => progress))
    end
end

end
