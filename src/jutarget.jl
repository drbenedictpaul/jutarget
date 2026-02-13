module juTarget

using Genie, Logging, TOML, DataFrames, CSV, Dates, FASTX, BioSequences, CodecZlib

export process_sample

# --- JULIA-NATIVE RD-ANALYZER ---

# This dictionary is ported directly from the Python script
const RD_SEQUENCES = Dict(
    "RD1" => ["GTCGGTGACAAAGCCGCTGCCGAGGAA", "GTCGTTGAGGACCTCGATGCCGTCG"],
    "RD2" => ["GTCGGTGACAAAGCCGCTGCCGAGGAA", "GTCGTTGAGGACCTCGATGCCGTCG"],
    "RD3" => ["CGCATCGTCGGCACCGTCGGCACCG", "GTGTCGTCGAAGCCCTCCCAGACGA"],
    "RD4" => ["CGGTTGACCGTGCCGTCGGCCTCGG", "GGTGTCGTCCGGGCCGAGACCGGCA"],
    "RD5" => ["CGGTTGACCGTGCCGTCGGCCTCGG", "GGTGTCGTCCGGGCCGAGACCGGCA"],
    "RD6" => ["CGGTTGACCGTGCCGTCGGCCTCGG", "GGTGTCGTCCGGGCCGAGACCGGCA"],
    "RD7" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"],
    "RD8" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"],
    "RD9" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"],
    "RD10" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"],
    "RD11" => ["AAGTCGGCGTCGCCGGCCGCGTCGA", "GGCGCCGTCGTCCTCGTCGGCCTCG"],
    "RD12" => ["AAGTCGGCGTCGCCGGCCGCGTCGA", "GGCGCCGTCGTCCTCGTCGGCCTCG"],
    "RD13" => ["TCGTCGGCACCGTCGACGTCGGCGA", "GCCGGAGTCGTCGACGTCGTCCGAC"],
    "RD14" => ["TCGTCGGCACCGTCGACGTCGGCGA", "GCCGGAGTCGTCGACGTCGTCCGAC"],
    "RD15" => ["CGCCGGCGTCGGCATCGTCGACGTC", "GCCGGAGTCGTCGACGTCGTCCGAC"],
    "RD16" => ["CGCCGGCGTCGGCATCGTCGACGTC", "GTCGACGTCGGCACCGGCGTCGGCG"],
    "RD17" => ["CGCCGGCGTCGGCATCGTCGACGTC", "GTCGACGTCGGCACCGGCGTCGGCG"],
    "RD18" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"],
    "RD19" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"],
    "RD20" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"],
    "RD21" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"],
    "RD22" => ["TCGTACAAGTCGTCGGCCGCGTCGT", "GTCGGCCTCGTCGGCCTCCTCGACG"],
    "RD23" => ["TCGTACAAGTCGTCGGCCGCGTCGT", "GTCGGCCTCGTCGGCCTCCTCGACG"],
    "RD24" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"],
    "RD25" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"],
    "RD26" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"],
    "RD27" => ["GTCGTCGTCGTCGGTGTCGTCGTCG", "GTCGTCGGCCGCCTCGTCGACGTCG"],
    "RD28" => ["GTCGTCGTCGTCGGTGTCGTCGTCG", "GTCGTCGGCCGCCTCGTCGACGTCG"]
);

function run_rd_analyzer_julia(fastq_path::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting Julia-native RD-Analyzer...")
    
    # Initialize counts for each RD to zero
    rd_hits = Dict{String, Int}(key => 0 for key in keys(RD_SEQUENCES))
    
    try
        # Use FASTX.jl to read the (potentially gzipped) FASTQ file
        reader = FASTQ.Reader(GzipDecompressorStream(open(fastq_path)))
        
        for record in reader
            seq_str = string(sequence(record))
            
            # Check for presence of each RD sequence
            for (rd_name, sequences) in RD_SEQUENCES
                # If we've already found this RD, no need to check again
                if rd_hits[rd_name] > 0 continue end
                
                fwd_seq, rev_seq = sequences[1], sequences[2]
                
                if occursin(fwd_seq, seq_str) || occursin(rev_seq, seq_str)
                    rd_hits[rd_name] += 1
                end
            end
        end
        close(reader)
        
        # Write the report
        report_path = joinpath(output_dir, "rd_analyzer_report.txt")
        open(report_path, "w") do f
            println(f, "# juTarget RD-Analyzer Report")
            println(f, "# Region\tStatus")
            sorted_rds = sort(collect(keys(rd_hits)))
            for rd_name in sorted_rds
                status = rd_hits[rd_name] > 0 ? "Present" : "Absent"
                println(f, "$rd_name\t$status")
            end
        end
        println(log_io, "--> RD-Analyzer finished successfully. Report at $report_path")
        return true

    catch e
        println(log_io, "ERROR in Julia-native RD-Analyzer: $e")
        return false
    end
end


# --- EXTERNAL TOOL WRAPPERS ---

function run_minimap2(config::Dict, sample_name::String, fastq_path::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting Minimap2 Alignment...")
    ref = config["paths"]["reference_genome"]
    exe = config["paths"]["minimap2"]
    sam_out = joinpath(output_dir, "$sample_name.sam")
    
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
        p = pipeline(cmd_view, cmd_sort)
        run(pipeline(p, stderr=log_io))
        
        rm(sam_in, force=true)
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
    
    cmd_pileup = `$exe mpileup -Ou -f $ref $bam_in`
    cmd_call = `$exe call -mv -o $vcf_out`
    
    try
        p = pipeline(cmd_pileup, cmd_call)
        run(pipeline(p, stderr=log_io))
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
        # 1. RD Analysis (Julia-native)
        update_status(channel, sample_name, "Running RD-Analyzer", 10)
        if !run_rd_analyzer_julia(fastq_path, sample_out_dir, log_io)
            @warn "RD-Analyzer step failed but continuing pipeline."
        end

        # 2. Alignment
        update_status(channel, sample_name, "Aligning (Minimap2)", 30)
        if !run_minimap2(config, sample_name, fastq_path, sample_out_dir, log_io)
            error("Minimap2 failed")
        end

        # 3. Sorting
        update_status(channel, sample_name, "Sorting (Samtools)", 60)
        if !run_samtools_sort(config, sample_name, sample_out_dir, log_io)
            error("Samtools sort failed")
        end

        # 4. Variant Calling
        update_status(channel, sample_name, "Calling Variants (Bcftools)", 80)
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
    if channel !== nothing && isopen(channel)
        try
            put!(channel, Dict(:sample => sample, :status => status, :progress => progress))
        catch e
             @warn "Failed to update status for $sample: channel might be closed."
        end
    end
end

end