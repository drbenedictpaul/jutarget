module juTarget

using Genie, Logging, TOML, DataFrames, CSV, Dates, FASTX, BioSequences, CodecZlib, DecisionTree, JLD2

export process_sample

# --- PUBLIC PLACEHOLDER FOR THE PROPRIETARY ML FUNCTION ---
# This function is the public-facing stub for the AI prediction.
# It informs the user that the proprietary module is not available.
function run_ml_prediction(config::Dict, sample_name::String, output_dir_base::String, log_io::IO)
    println(log_io, "--> Skipping AI Prediction: Proprietary module not available in public version.")
    sample_dir = joinpath(output_dir_base, sample_name)
    output_csv = joinpath(sample_dir, "clinical_drug_report.csv")
    df = DataFrame(Drug=[], Prediction=["Proprietary Module Needed"], Evidence=[], Mechanism=[])
    CSV.write(output_csv, df)
    return true
end

# --- CONDITIONAL INCLUDE FOR PROPRIETARY CODE ---
# This line checks for the existence of your secret ML file.
# If `jutarget_ml.jl` exists locally, it will be included, and its `run_ml_prediction`
# function will overwrite the placeholder function above. This file will be ignored by Git.
if isfile(joinpath(@__DIR__, "jutarget_ml.jl"))
    include("jutarget_ml.jl")
end

# --- ALL OTHER PUBLIC FUNCTIONS AND CONSTANTS ---

const RD_SEQUENCES = Dict(
    "RD1" => ["GTCGGTGACAAAGCCGCTGCCGAGGAA", "GTCGTTGAGGACCTCGATGCCGTCG"], "RD2" => ["GTCGGTGACAAAGCCGCTGCCGAGGAA", "GTCGTTGAGGACCTCGATGCCGTCG"],
    "RD3" => ["CGCATCGTCGGCACCGTCGGCACCG", "GTGTCGTCGAAGCCCTCCCAGACGA"], "RD4" => ["CGGTTGACCGTGCCGTCGGCCTCGG", "GGTGTCGTCCGGGCCGAGACCGGCA"],
    "RD5" => ["CGGTTGACCGTGCCGTCGGCCTCGG", "GGTGTCGTCCGGGCCGAGACCGGCA"], "RD6" => ["CGGTTGACCGTGCCGTCGGCCTCGG", "GGTGTCGTCCGGGCCGAGACCGGCA"],
    "RD7" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"], "RD8" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"],
    "RD9" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"], "RD10" => ["GATCGTCGGCTTCCGCTACGTCGGT", "GATGGAGTCGTCGCCGAGCATGTCG"],
    "RD11" => ["AAGTCGGCGTCGCCGGCCGCGTCGA", "GGCGCCGTCGTCCTCGTCGGCCTCG"], "RD12" => ["AAGTCGGCGTCGCCGGCCGCGTCGA", "GGCGCCGTCGTCCTCGTCGGCCTCG"],
    "RD13" => ["TCGTCGGCACCGTCGACGTCGGCGA", "GCCGGAGTCGTCGACGTCGTCCGAC"], "RD14" => ["TCGTCGGCACCGTCGACGTCGTCCGAC", "GCCGGAGTCGTCGACGTCGTCCGAC"],
    "RD15" => ["CGCCGGCGTCGGCATCGTCGACGTC", "GCCGGAGTCGTCGACGTCGTCCGAC"], "RD16" => ["CGCCGGCGTCGGCATCGTCGACGTC", "GTCGACGTCGGCACCGGCGTCGGCG"],
    "RD17" => ["CGCCGGCGTCGGCATCGTCGACGTC", "GTCGACGTCGGCACCGGCGTCGGCG"], "RD18" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"],
    "RD19" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"], "RD20" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"],
    "RD21" => ["GTCGTCGTCGGCGTCGGCACCATGA", "GACGAGACGATCGTCGCCGTCGTCG"], "RD22" => ["TCGTACAAGTCGTCGGCCGCGTCGT", "GTCGGCCTCGTCGGCCTCCTCGACG"],
    "RD23" => ["TCGTACAAGTCGTCGGCCGCGTCGT", "GTCGGCCTCGTCGGCCTCCTCGACG"], "RD24" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"],
    "RD25" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"],
    "RD26" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"],
    "RD27" => ["GTCGTCGTCGTCGGTGTCGTCGTCG", "GTCGTCGGCCGCCTCGTCGACGTCG"],
    "RD28" => ["GTCGTCGTCGTCGGTGTCGTCGTCG", "GTCGTCGGCCGCCTCGTCGACGTCG"]
);

function run_rd_analyzer_julia(fastq_path::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting Julia-native RD-Analyzer...")
    rd_hits = Dict{String, Int}(key => 0 for key in keys(RD_SEQUENCES))
    try
        reader = FASTQ.Reader(GzipDecompressorStream(open(fastq_path)))
        for record in reader
            seq_str = string(sequence(record))
            for (rd_name, sequences) in RD_SEQUENCES
                if rd_hits[rd_name] > 0; continue; end
                if occursin(sequences[1], seq_str) || occursin(sequences[2], seq_str)
                    rd_hits[rd_name] += 1
                end
            end
        end
        close(reader)
        report_path = joinpath(output_dir, "rd_analyzer_report.txt")
        open(report_path, "w") do f
            println(f, "# juTarget RD-Analyzer Report\n# Region\tStatus")
            sorted_rds = sort(collect(keys(rd_hits)))
            for rd_name in sorted_rds
                status = rd_hits[rd_name] > 0 ? "Present" : "Absent"
                println(f, "$rd_name\t$status")
            end
        end
        println(log_io, "--> RD-Analyzer finished successfully.")
        return true
    catch e
        println(log_io, "ERROR in Julia-native RD-Analyzer: $e")
        return false
    end
end

function run_vcf_filter_julia(vcf_in_path::String, vcf_out_path::String, log_io::IO)
    println(log_io, "--> Starting Julia-native VCF filtering (with Chromosome Fix)...")
    MIN_QUAL = 30.0; MIN_DP = 10; passed = 0; total = 0
    try
        open(vcf_out_path, "w") do writer
            for line in eachline(vcf_in_path)
                if startswith(line, "#"); println(writer, line); continue; end
                total += 1
                cols = split(line, '\t')
                if length(cols) < 8; continue; end
                qual = (cols[6] == ".") ? 0.0 : parse(Float64, cols[6])
                m = match(r"DP=(\d+)", cols[8])
                dp = (m !== nothing) ? parse(Int, m.captures[1]) : 0
                if qual >= MIN_QUAL && dp >= MIN_DP
                    cols[1] = "Chromosome"
                    println(writer, join(cols, '\t'))
                    passed += 1
                end
            end
        end
        println(log_io, "--> VCF filtering complete. Passed $(passed) of $(total) variants.")
        return true
    catch e
        println(log_io, "ERROR in VCF Filter: $e")
        return false
    end
end

function run_snpeff_annotation(sample_name::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting SnpEff Annotation...")
    in_vcf = joinpath(output_dir, "$sample_name.filtered.vcf")
    out_vcf = joinpath(output_dir, "$sample_name.ann.vcf")
    snpeff_jar = "/app/bin/snpEff/snpEff.jar"
    if !isfile(snpeff_jar)
        println(log_io, "ERROR: SnpEff Jar not found. Skipping annotation.")
        return false
    end
    cmd = `java -jar $snpeff_jar -noStats Mycobacterium_tuberculosis_h37rv $in_vcf`
    try
        run(pipeline(cmd, stdout=out_vcf, stderr=log_io))
        println(log_io, "    Annotation successful.")
        return true
    catch e
        println(log_io, "ERROR: SnpEff failed. Error: $e")
        try open(out_vcf, "w") do f; end; catch; end
        return false
    end
end

function run_minimap2(config::Dict, sample, fq, out, log)
    try; run(pipeline(`$(config["paths"]["minimap2"]) -ax map-ont -t 4 $(config["paths"]["reference_genome"]) $fq`, stdout=joinpath(out, "$sample.sam"), stderr=log)); return true
    catch e; println(log, "Error in minimap2: $e"); return false; end
end

function run_samtools_sort(config::Dict, sample, out, log)
    try; run(pipeline(pipeline(`$(config["paths"]["samtools"]) view -bS $(joinpath(out, "$sample.sam"))`, `$(config["paths"]["samtools"]) sort -o $(joinpath(out, "$sample.sorted.bam")) -`), stderr=log)); rm(joinpath(out, "$sample.sam"), force=true); return true
    catch e; println(log, "Error in samtools: $e"); return false; end
end

function run_bcftools_call(config::Dict, sample, out, log)
    try; run(pipeline(pipeline(`$(config["paths"]["bcftools"]) mpileup -Ou -f $(config["paths"]["reference_genome"]) $(joinpath(out, "$sample.sorted.bam"))`, `$(config["paths"]["bcftools"]) call -mv -o $(joinpath(out, "$sample.raw.vcf"))`), stderr=log)); return true
    catch e; println(log, "Error in bcftools: $e"); return false; end
end

function archive_results(sample_name::String, output_dir_base::String, log_io::IO)
    println(log_io, "--> Archiving results...")
    try
        sample_dir = joinpath(output_dir_base, sample_name)
        rd_report = joinpath(sample_dir, "rd_analyzer_report.txt")
        drug_report = joinpath(sample_dir, "clinical_drug_report.csv")
        vcf_file = joinpath(sample_dir, "$sample_name.ann.vcf")
        timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
        archive_dir = joinpath(homedir(), "juTarget_results", "$(sample_name)_$(timestamp)")
        mkpath(archive_dir)
        if isfile(rd_report); cp(rd_report, joinpath(archive_dir, "rd_analyzer_report.txt")); end
        if isfile(drug_report); cp(drug_report, joinpath(archive_dir, "clinical_drug_report.csv")); end
        if isfile(vcf_file); cp(vcf_file, joinpath(archive_dir, "variants.vcf")); end
        println(log_io, "--> Results successfully archived to: $archive_dir")
        return true
    catch e
        println(log_io, "Error during archiving: $e")
        return false
    end
end

function update_status(channel, sample, status, progress)
    if channel !== nothing && isopen(channel)
        try; put!(channel, Dict(:sample => sample, :status => status, :progress => progress)); catch; end
    end
end

function process_sample(config::Dict, sample_name::String, fastq_path::String, output_dir_base::String, channel, log_io::IO)
    sample_out = joinpath(output_dir_base, sample_name); mkpath(sample_out)
    try
        update_status(channel, sample_name, "RD-Analyzer", 10)
        run_rd_analyzer_julia(fastq_path, sample_out, log_io)
        update_status(channel, sample_name, "Aligning", 20)
        if !run_minimap2(config, sample_name, fastq_path, sample_out, log_io) error("Minimap2 failed") end
        update_status(channel, sample_name, "Sorting", 40)
        if !run_samtools_sort(config, sample_name, sample_out, log_io) error("Samtools failed") end
        update_status(channel, sample_name, "Variant Calling", 60)
        if !run_bcftools_call(config, sample_name, sample_out, log_io) error("Bcftools failed") end
        raw_vcf = joinpath(sample_out, "$sample_name.raw.vcf")
        filtered_vcf = joinpath(sample_out, "$sample_name.filtered.vcf")
        update_status(channel, sample_name, "Filtering Variants", 75)
        if !run_vcf_filter_julia(raw_vcf, filtered_vcf, log_io) error("Filter failed") end
        rm(raw_vcf, force=true)
        update_status(channel, sample_name, "Annotating", 85)
        run_snpeff_annotation(sample_name, sample_out, log_io)
        update_status(channel, sample_name, "AI Prediction", 95)
        run_ml_prediction(config, sample_name, output_dir_base, log_io)
        update_status(channel, sample_name, "Archiving", 99)
        archive_results(sample_name, output_dir_base, log_io)
        update_status(channel, sample_name, "Completed", 100)
    catch e
        println(log_io, "FATAL ERROR in pipeline: $e")
        update_status(channel, sample_name, "Failed", 0)
        rethrow(e)
    end
end

end