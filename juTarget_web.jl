using Genie, Genie.Router, Genie.Renderer.Json, Genie.Renderer.Html
using TOML, Base.Threads, Dates

include("src/jutarget.jl")
using .juTarget

# --- CONFIGURATION ---
const USER_HOME = homedir()
const INPUT_DIR = joinpath(USER_HOME, "juTarget_input")
const OUTPUT_DIR = joinpath(USER_HOME, "juTarget_output")
const STATE_FILE = joinpath(OUTPUT_DIR, "run_state.txt")
const JOB_STATUS = Dict{String, Dict{Symbol, Any}}()
const JOB_LOCK = ReentrantLock()
const STATUS_CHANNEL = Channel{Dict}(256)

# --- HELPER FUNCTIONS ---

function group_fastq_files_by_sample(base_dir::String)
    grouped_files = Dict{String, Vector{String}}()
    if !isdir(base_dir); return grouped_files; end

    regex = r"(barcode\d+)"

    # walkdir will recursively scan all subdirectories
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
    
    if isempty(grouped_files)
        @warn "No files matching 'barcodeXX' pattern found in any subdirectory of $base_dir"
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
        return json(Dict("success" => false, "message" => "No FASTQ files with 'barcodeXX' pattern found in input directory."))
    end

    lock(JOB_LOCK) do
        empty!(JOB_STATUS)
        for name in keys(sample_groups)
            JOB_STATUS[name] = Dict(:status => "Queued", :progress => 0)
        end
    end

    @async begin
        concat_dir = joinpath(OUTPUT_DIR, "0_concatenated")
        mkpath(concat_dir)

        for (name, files) in sample_groups
            juTarget.update_status(STATUS_CHANNEL, name, "Concatenating files", 5)
            concatenated_path = joinpath(concat_dir, name * ".fastq.gz")
            
            try
                run(pipeline(`cat $files`, stdout=concatenated_path))
            catch e
                @error "Failed to concatenate files for sample $name: $e"
                juTarget.update_status(STATUS_CHANNEL, name, "Failed: Concatenation", 0)
                continue
            end

            spawn_pipeline_task(config, name, concatenated_path, OUTPUT_DIR, STATUS_CHANNEL)
        end
    end

    return json(Dict("success" => true, "message" => "Pipeline started for $(length(sample_groups)) samples."))
end


route("/get-status") do
    lock(JOB_LOCK) do
        return json(JOB_STATUS)
    end
end

# --- STATUS LISTENER ---
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
        println("Channel error: $e")
    end
end

# --- INITIALIZATION ---
println("Initializing juTarget Server...")
mkpath(INPUT_DIR)
mkpath(OUTPUT_DIR)

Genie.up(8000, "0.0.0.0", async=false)