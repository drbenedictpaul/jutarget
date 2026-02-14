using Genie, Genie.Router, Genie.Renderer.Json, Genie.Renderer.Html
using TOML, Base.Threads, Dates, CSV, DataFrames

include("src/jutarget.jl")
using .juTarget

# --- CONFIGURATION ---
const USER_HOME = homedir()
const INPUT_DIR = joinpath(USER_HOME, "juTarget_input")
const OUTPUT_DIR = joinpath(USER_HOME, "juTarget_output")
const ARCHIVE_DIR = joinpath(USER_HOME, "juTarget_results")
const STATE_FILE = joinpath(OUTPUT_DIR, "run_state.txt")
const JOB_STATUS = Dict{String, Dict{Symbol, Any}}()
const JOB_LOCK = ReentrantLock()
const STATUS_CHANNEL = Channel{Dict}(256)

# --- HELPER FUNCTIONS ---

function group_fastq_files_by_sample(base_dir::String)
    grouped_files = Dict{String, Vector{String}}()
    if !isdir(base_dir); return grouped_files; end
    regex = r"(barcode\d+)"
    for (root, dirs, files) in walkdir(base_dir)
        for filename in files
            if endswith(filename, ".fastq.gz") || endswith(filename, ".fastq")
                m = match(regex, filename)
                if m !== nothing
                    sample_name = m.match
                    if !haskey(grouped_files, sample_name); grouped_files[sample_name] = []; end
                    push!(grouped_files[sample_name], joinpath(root, filename))
                end
            end
        end
    end
    return grouped_files
end

function spawn_pipeline_task(config, name, fastq_path, output_dir, channel)
    return Threads.@spawn begin
        log_dir = joinpath("public", "logs"); mkpath(log_dir)
        log_file = joinpath(log_dir, "$(name).log")
        try
            open(log_file, "w+") do log_io
                juTarget.process_sample(config, name, fastq_path, output_dir, channel, log_io)
            end
        catch e; juTarget.update_status(channel, name, "Failed", 0); end
    end
end

# --- ROUTES ---

route("/") do; serve_static_file("index.html"); end

route("/start-pipeline", method = "POST") do
    config = TOML.parsefile("config.toml")
    sample_groups = group_fastq_files_by_sample(INPUT_DIR)
    if isempty(sample_groups); return json(Dict("success" => false, "message" => "No FASTQ files found.")); end
    lock(JOB_LOCK) do; empty!(JOB_STATUS); for name in keys(sample_groups); JOB_STATUS[name] = Dict(:status => "Queued", :progress => 0); end; end
    @async begin
        concat_dir = joinpath(OUTPUT_DIR, "0_concatenated"); mkpath(concat_dir)
        for (name, files) in sample_groups
            juTarget.update_status(STATUS_CHANNEL, name, "Concatenating", 5)
            concatenated_path = joinpath(concat_dir, name * ".fastq.gz")
            try; run(pipeline(`cat $files`, stdout=concatenated_path)); catch e; juTarget.update_status(STATUS_CHANNEL, name, "Failed", 0); continue; end
            spawn_pipeline_task(config, name, concatenated_path, OUTPUT_DIR, STATUS_CHANNEL)
        end
    end
    return json(Dict("success" => true, "message" => "Pipeline started."))
end

route("/get-status") do; lock(JOB_LOCK) do; return json(JOB_STATUS); end; end

route("/list-results") do
    if !isdir(ARCHIVE_DIR); mkpath(ARCHIVE_DIR); return json([]); end
    folders = filter(x -> isdir(joinpath(ARCHIVE_DIR, x)), readdir(ARCHIVE_DIR))
    sort!(folders, by = x -> stat(joinpath(ARCHIVE_DIR, x)).mtime, rev=true)
    return json(folders)
end

route("/get-result-data/:folder") do
    folder = params(:folder)
    target_path = joinpath(ARCHIVE_DIR, folder)
    if !isdir(target_path); return json(Dict("success" => false)); end
    rd_file = joinpath(target_path, "rd_analyzer_report.txt")
    rd_content = isfile(rd_file) ? read(rd_file, String) : "No RD report found."
    drug_file = joinpath(target_path, "clinical_drug_report.csv"); drug_data = []
    if isfile(drug_file); try; df = CSV.read(drug_file, DataFrame); drug_data = [Dict(col => val for (col, val) in zip(names(df), row)) for row in eachrow(df)]; catch; end; end
    return json(Dict("success" => true, "rd_report" => rd_content, "drug_report" => drug_data))
end

# --- REPORT GENERATION ---

route("/print-report/:folder") do
    folder = params(:folder)
    target_path = joinpath(ARCHIVE_DIR, folder)
    if !isdir(target_path); return "Report not found"; end
    
    drug_file = joinpath(target_path, "clinical_drug_report.csv")
    rd_file = joinpath(target_path, "rd_analyzer_report.txt")
    
    drug_rows = ""
    if isfile(drug_file)
        df = CSV.read(drug_file, DataFrame)
        for row in eachrow(df)
            color = row.Prediction == "RESISTANT" ? "#d32f2f" : "#388e3c"
            drug_rows *= "<tr><td>$(row.Drug)</td><td style='color:$color; font-weight:bold;'>$(row.Prediction)</td><td>$(row.Evidence)</td><td>$(row.Mechanism)</td></tr>"
        end
    end
    
    rd_content = isfile(rd_file) ? read(rd_file, String) : "N/A"
    
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Clinical Report - $folder</title>
        <style>
            body { font-family: sans-serif; padding: 40px; color: #333; max-width: 800px; margin: auto; }
            .header { border-bottom: 2px solid #5a4b81; padding-bottom: 20px; margin-bottom: 30px; }
            h1 { color: #5a4b81; margin: 0; }
            h2 { font-size: 18px; border-bottom: 1px solid #ccc; padding-bottom: 5px; margin-top: 30px; }
            table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 12px; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #f4f4f4; }
            .footer { margin-top: 50px; font-size: 10px; color: #777; border-top: 1px solid #eee; padding-top: 10px; text-align: right; }
            @media print { body { padding: 0; } button { display: none; } }
        </style>
    </head>
    <body onload="window.print()">
        <div style="text-align:right;">
            <button onclick="window.print()" style="padding:10px 20px; background:#5a4b81; color:white; border:none; cursor:pointer;">Print / Save as PDF</button>
        </div>
        
        <div class="header">
            <h1>Molecular Drug Susceptibility Report</h1>
            <p><strong>Sample ID:</strong> $folder</p>
            <p><strong>Date:</strong> $(Dates.format(now(), "dd/mm/yyyy"))</p>
            <p><strong>Method:</strong> Nanopore tNGS</p>
            <p><strong>Data Analysis:</strong> juTarget</p>
        </div>

        <h2>Drug Resistance Profile</h2>
        <table>
            <thead><tr><th>Drug</th><th>Prediction</th><th>Mutation Evidence</th><th>Mechanism</th></tr></thead>
            <tbody>$drug_rows</tbody>
        </table>

        <h2>Lineage / Strain Analysis (RD-Analyzer)</h2>
        <pre style="background:#f9f9f9; padding:10px; font-size:11px;">$rd_content</pre>

        <div class="footer">
            Report by: juTarget v1.0
        </div>
    </body>
    </html>
    """
end

@async while isopen(STATUS_CHANNEL); try; update = take!(STATUS_CHANNEL); lock(JOB_LOCK) do; if haskey(JOB_STATUS, update[:sample]); JOB_STATUS[update[:sample]][:status] = update[:status]; JOB_STATUS[update[:sample]][:progress] = update[:progress]; end; end; catch; end; end

# --- STARTUP BANNER & INITIALIZATION ---

println("""
======================================================
      juTarget v1.0 - Targeted NGS Analysis

           Developed by: Dr. Benedict Christopher Paul
           Website: http://www.drpaul.cc
======================================================
Press [Enter] to launch the juTarget server...
""")

readline()

println("\nStarting the juTarget application server...")
println("Initializing juTarget Server...")
mkpath(INPUT_DIR); mkpath(OUTPUT_DIR); mkpath(ARCHIVE_DIR)

Genie.up(8000, "0.0.0.0", async=false)