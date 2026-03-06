# --- HARDWARE AUTHENTICATION (Final Multi-License) ---

# List of all authorized machine ID pairs (UUID, Baseboard)
const BLESSED_MACHINES = [
    # Friend's Machine 1
    ("4c4c4544-0053-4d10-8051-b6c04f424e33", "/6SMQBN3/CNPE10022F0BP4/"),
    
    # Friend's Machine 2
    ("4c4c4544-0048-5a10-8052-c6c04f505433", "/FHZRPT3//FHZRPT3/CNFCW0028U00G4//"),

    # Developer's Machine (Your Fedora Machine)
    ("7c0ce48b-275f-11e3-aa05-28d2442e1ee3", "/1005943800730/YB01410308/"),
]

# Get IDs passed from the launcher
const CURRENT_UUID      = get(ENV, "JUTARGET_HW_UUID", "unauthorized")
const CURRENT_BASEBOARD = get(ENV, "JUTARGET_HW_BASEBOARD", "unauthorized")
const CURRENT_MACHINE   = (CURRENT_UUID, CURRENT_BASEBOARD)

# Final, secure check against the list
if !(CURRENT_MACHINE in BLESSED_MACHINES)
    println("""
    ==================================================================
    AUTHENTICATION FAILED: LICENSE ERROR
    ------------------------------------------------------------------
    This application is not licensed for this machine.
    Please contact Dr. Paul (www.drpaul.cc) for a license.
    ==================================================================
    """)
    exit(1)
end

println("--> Hardware Authentication Successful.")

# --- APPLICATION START ---
using Genie, Genie.Router, Genie.Renderer.Json, Genie.Renderer.Html
using TOML, Base.Threads, Dates, CSV, DataFrames

include("src/jutarget.jl")
using .juTarget

# --- CONFIGURATION ---
const USER_HOME = "/root"
const INPUT_DIR = joinpath(USER_HOME, "juTarget_input")
const OUTPUT_DIR = joinpath(USER_HOME, "juTarget_output")
const ARCHIVE_DIR = joinpath(USER_HOME, "juTarget_results")
const JOB_STATUS = Dict{String, Dict{Symbol, Any}}()
const JOB_LOCK = ReentrantLock()
const STATUS_CHANNEL = Channel{Dict}(256)
const RAM_PER_SAMPLE_GB = 4
const MAX_CONCURRENT_JOBS = 8

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
                    if !haskey(grouped_files, sample_name)
                        grouped_files[sample_name] = []
                    end
                    push!(grouped_files[sample_name], joinpath(root, filename))
                end
            end
        end
    end
    return grouped_files
end

function spawn_pipeline_task(config, name, fastq_path, output_dir, channel)
    return Threads.@spawn begin
        log_dir = joinpath("public", "logs")
        mkpath(log_dir)
        log_file = joinpath(log_dir, "$(name).log")
        try
            open(log_file, "w+") do log_io
                juTarget.process_sample(config, name, fastq_path, output_dir, channel, log_io)
            end
        catch e
            println("ERROR in spawned task for sample $name: $e")
            juTarget.update_status(channel, name, "Failed", 0)
        end
    end
end

# --- ROUTES ---
route("/") do
    serve_static_file("index.html")
end

route("/start-pipeline", method = "POST") do
    config = TOML.parsefile("config.toml")
    sample_groups = group_fastq_files_by_sample(INPUT_DIR)
    if isempty(sample_groups)
        return json(Dict("success" => false, "message" => "No FASTQ files found."))
    end
    
    lock(JOB_LOCK) do
        empty!(JOB_STATUS)
        for name in keys(sample_groups)
            JOB_STATUS[name] = Dict(:status => "Queued", :progress => 0)
        end
    end
    
    @async begin
        total_ram_gb = Sys.total_memory() / (1024^3)
        calculated_jobs = floor(Int, total_ram_gb / RAM_PER_SAMPLE_GB)
        max_parallel_jobs = min(MAX_CONCURRENT_JOBS, max(1, calculated_jobs))
        println("\n--- Job Scheduler Initialized ---\nMax Parallel Jobs: $max_parallel_jobs")
        
        pending_samples = collect(pairs(sample_groups))
        running_tasks = Task[]
        concat_dir = joinpath(OUTPUT_DIR, "0_concatenated")
        mkpath(concat_dir)
        
        while !isempty(pending_samples) || !isempty(running_tasks)
            filter!(t -> !istaskdone(t), running_tasks)
            
            while length(running_tasks) < max_parallel_jobs && !isempty(pending_samples)
                (name, files) = popfirst!(pending_samples)
                juTarget.update_status(STATUS_CHANNEL, name, "Concatenating", 5)
                concatenated_path = joinpath(concat_dir, name * ".fastq.gz")
                try
                    run(pipeline(`cat $files`, stdout=concatenated_path))
                catch e
                    juTarget.update_status(STATUS_CHANNEL, name, "Failed", 0)
                    continue
                end
                task = spawn_pipeline_task(config, name, concatenated_path, OUTPUT_DIR, STATUS_CHANNEL)
                push!(running_tasks, task)
            end
            sleep(5)
        end
    end
    return json(Dict("success" => true, "message" => "Pipeline started."))
end

route("/get-status") do
    lock(JOB_LOCK) do
        return json(JOB_STATUS)
    end
end

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
    
    drug_file = joinpath(target_path, "clinical_drug_report.csv")
    drug_data = []
    if isfile(drug_file)
        try
            df = CSV.read(drug_file, DataFrame)
            drug_data = [Dict(col => val for (col, val) in zip(names(df), row)) for row in eachrow(df)]
        catch
            # Handle empty or malformed file
        end
    end
    return json(Dict("success" => true, "rd_report" => rd_content, "drug_report" => drug_data))
end

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
    <!DOCTYPE html><html><head><title>Clinical Report - $folder</title><style>body{font-family:sans-serif;padding:40px;max-width:800px;margin:auto}h1{color:#5a4b81}.footer{margin-top:50px;font-size:10px;text-align:right}</style></head><body onload="window.print()"><div style="text-align:right"><button onclick="window.print()">Print / Save PDF</button></div><h1>Molecular Drug Susceptibility Report</h1><p><strong>Sample ID:</strong> $folder</p><p><strong>Date:</strong> $(Dates.format(now(), "dd/mm/yyyy"))</p><p><strong>Method:</strong> Nanopore tNGS</p><p><strong>Data Analysis:</strong> juTarget</p><h2>Drug Resistance Profile</h2><table style="width:100%;border-collapse:collapse"><thead><tr><th style="border:1px solid #ddd;padding:8px;text-align:left">Drug</th><th style="border:1px solid #ddd;padding:8px;text-align:left">Prediction</th><th style="border:1px solid #ddd;padding:8px;text-align:left">Evidence</th><th style="border:1px solid #ddd;padding:8px;text-align:left">Mechanism</th></tr></thead><tbody>$drug_rows</tbody></table><h2>Lineage Analysis</h2><pre>$rd_content</pre><div class="footer">Report by: juTarget</div></body></html>
    """
end

@async while isopen(STATUS_CHANNEL)
    try
        update = take!(STATUS_CHANNEL)
        lock(JOB_LOCK) do
            if haskey(JOB_STATUS, update[:sample])
                JOB_STATUS[update[:sample]][:status] = update[:status]
                JOB_STATUS[update[:sample]][:progress] = update[:progress]
            end
        end
    catch e
        # Handle channel being closed
    end
end

# --- STARTUP ---
println("======================================================")
println("      juTarget v1.0 - Targeted NGS Analysis")
println("           Developed by: Dr. Benedict Christopher Paul")
println("======================================================")
println("\nStarting server...")
mkpath(INPUT_DIR); mkpath(OUTPUT_DIR); mkpath(ARCHIVE_DIR)

Genie.up(8001, "0.0.0.0", async=false)