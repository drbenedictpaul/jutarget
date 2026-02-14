module juTarget

using Genie, Logging, TOML, DataFrames, CSV, Dates, FASTX, BioSequences, CodecZlib, DecisionTree, JLD2

export process_sample

# --- CONSTANTS ---

if !isdefined(@__MODULE__, :AA_FULL_PROPS)
    const AA_FULL_PROPS = Dict{String, Vector{Float64}}(
        "Ala" => [ 1.8,  89.1,  6.00,  88.6,  8.1,  0,  0,  1.42, 0.83, 0.66, 0.0],
        "Arg" => [-4.5, 174.2, 10.76, 173.4, 10.5,  5,  0,  0.98, 0.93, 0.95, 0.0],
        "Asn" => [-3.5, 132.1,  5.41, 114.1, 11.6,  2,  2,  0.67, 0.89, 1.56, 0.0],
        "Asp" => [-3.5, 133.1,  2.77, 111.1, 13.0,  0,  4,  1.01, 0.54, 1.46, 0.0],
        "Cys" => [ 2.5, 121.2,  5.07, 108.5,  5.5,  0,  0,  0.70, 1.19, 1.19, 0.0],
        "Gln" => [-3.5, 146.2,  5.65, 143.8, 10.5,  2,  2,  1.11, 1.10, 0.98, 0.0],
        "Glu" => [-3.5, 147.1,  3.22, 138.4, 12.3,  0,  4,  1.51, 0.37, 0.74, 0.0],
        "Gly" => [-0.4,  75.1,  5.97,  60.1,  9.0,  0,  0,  0.57, 0.75, 1.56, 0.0],
        "His" => [-3.2, 155.2,  7.59, 153.2, 10.4,  2,  2,  1.00, 0.87, 0.95, 1.0],
        "Ile" => [ 4.5, 131.2,  6.02, 166.7,  5.2,  0,  0,  1.08, 1.60, 0.47, 0.0],
        "Leu" => [ 3.8, 131.2,  5.98, 166.7,  4.9,  0,  0,  1.21, 1.30, 0.59, 0.0],
        "Lys" => [-3.9, 146.2,  9.74, 168.6, 11.3,  3,  0,  1.16, 0.74, 1.01, 0.0],
        "Met" => [ 1.9, 149.2,  5.74, 162.9,  5.7,  0,  0,  1.45, 1.05, 0.60, 0.0],
        "Phe" => [ 2.8, 165.2,  5.48, 189.9,  5.2,  0,  0,  1.13, 1.38, 0.60, 1.0],
        "Pro" => [-1.6, 115.1,  6.30, 112.7,  8.0,  0,  0,  0.57, 0.55, 1.52, 0.0],
        "Ser" => [-0.8, 105.1,  5.68,  89.0,  9.2,  2,  2,  0.77, 0.75, 1.43, 0.0],
        "Thr" => [-0.7, 119.1,  5.60, 116.1,  8.6,  2,  2,  0.83, 1.19, 0.96, 0.0],
        "Trp" => [-0.9, 204.2,  5.89, 227.8,  5.4,  1,  0,  1.08, 1.37, 0.96, 1.0],
        "Tyr" => [-1.3, 181.2,  5.66, 193.6,  6.2,  1,  1,  0.69, 1.47, 1.14, 1.0],
        "Val" => [ 4.2, 117.1,  5.96, 140.0,  5.9,  0,  0,  1.06, 1.70, 0.50, 0.0],
        "Stop" => zeros(11), "Ter"=>zeros(11), "X"=>zeros(11)
    )

    const TRACKED_DRUGS = [
        "Rifampicin", "Isoniazid", "Pyrazinamide", "Ethambutol", 
        "Fluoroquinolones", "Streptomycin", "Amikacin", "Kanamycin", 
        "Capreomycin", "Ethionamide", "Bedaquiline", "Linezolid", 
        "Clofazimine", "Delamanid"
    ]
end

# --- CORE LOGIC ---

function run_ml_prediction(config::Dict, sample_name::String, output_dir_base::String, log_io::IO)
    println(log_io, "--> Starting AI Resistance Prediction...")
    vcf_path = joinpath(output_dir_base, sample_name, "$sample_name.filtered.vcf")
    ref_dir = dirname(config["paths"]["reference_genome"])
    model_path = joinpath(ref_dir, "chem_resistance_model.jld2")
    training_data_path = joinpath(ref_dir, "training_data.csv")
    output_csv = joinpath(output_dir_base, sample_name, "clinical_drug_report.csv")

    if !isfile(vcf_path) || !isfile(model_path); println(log_io, "Error: VCF or Model missing."); return false; end
    
    try
        model = JLD2.load(model_path, "model")
        ref_df = CSV.read(training_data_path, DataFrame)
        pos_lookup = Dict{Int, Tuple{String, String}}()
        for row in eachrow(ref_df); pos_lookup[row.genomic_position] = (String(row.wt_residue), String(row.mut_residue)); end

        evidence_map = Dict{String, Vector{Tuple{String, String}}}()

        for line in eachline(vcf_path)
            if startswith(line, "#"); continue; end
            cols = split(line, '\t'); if length(cols) < 2; continue; end
            pos = parse(Int, cols[2])
            if !haskey(pos_lookup, pos); continue; end
            
            wt_aa, mut_aa = pos_lookup[pos]
            if !haskey(AA_FULL_PROPS, wt_aa) || !haskey(AA_FULL_PROPS, mut_aa); continue; end
            
            wp, mp = AA_FULL_PROPS[wt_aa], AA_FULL_PROPS[mut_aa]
            feats = zeros(Float64, 30); feats[1] = Float64(pos)
            for k in 1:10; feats[1+k] = wp[k]; feats[11+k] = mp[k]; end
            feats[22]=wp[11]; feats[23]=mp[11]; feats[24]=mp[1]-wp[1]; feats[25]=mp[4]-wp[4]
            feats[26]=mp[5]-wp[5]; feats[27]=((wp[3]<6 && mp[3]>7.5) || (wp[3]>7.5 && mp[3]<6)) ? 1.0 : 0.0
            feats[28]=(wp[6]+wp[7])-(mp[6]+mp[7]); feats[29]=((mut_aa=="Pro"||mut_aa=="Gly") && (wt_aa!="Pro"&&wt_aa!="Gly")) ? 1.0 : 0.0
            feats[30]=(wp[11]==1.0 && mp[11]==0.0) ? 1.0 : 0.0

            pred_drug = apply_forest(model, feats)
            
            mech = "Biophysical Shift"
            if abs(feats[25]) > 30.0; mech = "Steric Hindrance (Vol)"; elseif feats[27] == 1.0; mech = "Charge Inversion (pI)";
            elseif feats[29] == 1.0; mech = "Helix Breaking"; elseif abs(feats[24]) > 3.0; mech = "Hydrophobic Disruption"; end

            if !haskey(evidence_map, pred_drug); evidence_map[pred_drug] = []; end
            push!(evidence_map[pred_drug], ("Pos $pos ($wt_aa->$mut_aa)", mech))
        end

        final_df = DataFrame(Drug=[], Prediction=[], Evidence=[], Mechanism=[])
        for drug in TRACKED_DRUGS
            if haskey(evidence_map, drug)
                ev_list = evidence_map[drug]
                push!(final_df, (drug, "RESISTANT", join([e[1] for e in ev_list], "; "), join(unique([e[2] for e in ev_list]), "; ")))
            else
                push!(final_df, (drug, "SUSCEPTIBLE", "None", "-"))
            end
        end
        CSV.write(output_csv, final_df)
        return true
    catch e; println(log_io, "ERROR in AI Prediction: $e"); return false; end
end

function archive_results(sample_name::String, output_dir_base::String, log_io::IO)
    println(log_io, "--> Archiving results to centralized database...")
    try
        # Define source files
        sample_dir = joinpath(output_dir_base, sample_name)
        rd_report = joinpath(sample_dir, "rd_analyzer_report.txt")
        drug_report = joinpath(sample_dir, "clinical_drug_report.csv")
        vcf_file = joinpath(sample_dir, "$sample_name.filtered.vcf")

        # Define destination
        timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
        # Creates: ~/juTarget_results/Barcode62_2026-02-14_103000/
        archive_dir = joinpath(homedir(), "juTarget_results", "$(sample_name)_$(timestamp)")
        mkpath(archive_dir)

        # Copy files
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
    "RD25" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"], "RD26" => ["GTCGACGTCGGCACCGAAGTCGTCG", "GTCCTCGTCGGCACCGGCAAGTCGT"],
    "RD27" => ["GTCGTCGTCGTCGGTGTCGTCGTCG", "GTCGTCGGCCGCCTCGTCGACGTCG"], "RD28" => ["GTCGTCGTCGTCGGTGTCGTCGTCG", "GTCGTCGGCCGCCTCGTCGACGTCG"]
);

function run_rd_analyzer_julia(fastq_path::String, output_dir::String, log_io::IO)
    println(log_io, "--> Starting Julia-native RD-Analyzer...")
    rd_hits = Dict{String, Int}(key => 0 for key in keys(RD_SEQUENCES))
    try
        reader = FASTQ.Reader(GzipDecompressorStream(open(fastq_path)))
        for record in reader
            seq_str = string(sequence(record)); for (rd, seqs) in RD_SEQUENCES; if rd_hits[rd]>0 continue end; if occursin(seqs[1], seq_str)||occursin(seqs[2], seq_str) rd_hits[rd]+=1 end end
        end
        close(reader)
        open(joinpath(output_dir, "rd_analyzer_report.txt"), "w") do f; println(f, "# Region\tStatus"); for rd in sort(collect(keys(rd_hits))); println(f, "$rd\t$(rd_hits[rd]>0 ? "Present" : "Absent")"); end; end
        return true
    catch e; println(log_io, "ERROR in RD-Analyzer: $e"); return false; end
end

function run_vcf_filter_julia(vcf_in_path::String, vcf_out_path::String, log_io::IO)
    println(log_io, "--> Starting Julia-native VCF filtering...")
    MIN_QUAL=30.0; MIN_DP=10; passed=0
    try
        open(vcf_out_path, "w") do w
            for line in eachline(vcf_in_path)
                if startswith(line, "#"); println(w, line); continue; end
                cols=split(line, '\t'); if length(cols)<8 continue end
                qual=(cols[6]==".") ? 0.0 : parse(Float64, cols[6]); m=match(r"DP=(\d+)", cols[8]); dp=(m!==nothing) ? parse(Int, m.captures[1]) : 0
                if qual>=MIN_QUAL && dp>=MIN_DP; println(w, line); passed+=1; end
            end
        end
        println(log_io, "--> VCF filtering complete. Passed: $passed"); return true
    catch e; println(log_io, "ERROR in VCF Filter: $e"); return false; end
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

function process_sample(config::Dict, sample_name::String, fastq_path::String, output_dir_base::String, channel, log_io::IO)
    sample_out = joinpath(output_dir_base, sample_name); mkpath(sample_out)
    try
        update_status(channel, sample_name, "RD-Analyzer", 10); run_rd_analyzer_julia(fastq_path, sample_out, log_io)
        update_status(channel, sample_name, "Aligning", 25); if !run_minimap2(config, sample_name, fastq_path, sample_out, log_io) error("Minimap2 failed") end
        update_status(channel, sample_name, "Sorting", 50); if !run_samtools_sort(config, sample_name, sample_out, log_io) error("Samtools failed") end
        update_status(channel, sample_name, "Variant Calling", 75); if !run_bcftools_call(config, sample_name, sample_out, log_io) error("Bcftools failed") end
        update_status(channel, sample_name, "Filtering Variants", 85); if !run_vcf_filter_julia(joinpath(sample_out, "$sample_name.raw.vcf"), joinpath(sample_out, "$sample_name.filtered.vcf"), log_io) error("Filter failed") end
        rm(joinpath(sample_out, "$sample_name.raw.vcf"), force=true)
        update_status(channel, sample_name, "AI Prediction", 95); run_ml_prediction(config, sample_name, output_dir_base, log_io)
        
        # Archive Results
        update_status(channel, sample_name, "Archiving", 99)
        archive_results(sample_name, output_dir_base, log_io)

        update_status(channel, sample_name, "Completed", 100)
    catch e
        println(log_io, "FATAL ERROR: $e"); update_status(channel, sample_name, "Failed", 0); rethrow(e)
    end
end

function update_status(channel, sample, status, progress)
    if channel !== nothing && isopen(channel); try; put!(channel, Dict(:sample => sample, :status => status, :progress => progress)); catch; end; end
end

end