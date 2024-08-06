# Use Ubuntu 22.04 as the base image
# This provides a stable and well-supported environment for our build
FROM ubuntu:22.04

# Set the environment to non-interactive to avoid interactive prompts during package installations
# This is crucial for automated builds to prevent hanging on user input prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages, including development tools, Clang, RocksDB, and utilities
# We use --no-install-recommends to minimize the image size by avoiding unnecessary packages
RUN echo "Starting installation of necessary packages including Clang and RocksDB..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libc6-dev \
        m4 \
        g++-multilib \
        autoconf \
        libtool \
        libncurses-dev \
        unzip \
        git \
        python3 \
        python3-zmq \
        python3-pip \
        zlib1g-dev \
        wget \
        curl \
        bsdmainutils \
        automake \
        cmake \
        bear \
        xz-utils \
        clang \
        librocksdb-dev \
        graphviz \
        xdot \
        binutils \
        openjdk-11-jdk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "Package installation completed successfully."

# Install Boost
RUN wget https://boostorg.jfrog.io/artifactory/main/release/1.82.0/source/boost_1_82_0.tar.gz && \
    tar -xzf boost_1_82_0.tar.gz && \
    cd boost_1_82_0 && \
    ./bootstrap.sh --prefix=/usr/local && \
    ./b2 install && \
    cd .. && \
    rm -rf boost_1_82_0 boost_1_82_0.tar.gz

# Set Boost-related environment variables
ENV BOOST_ROOT=/usr/local
ENV BOOST_INCLUDEDIR=/usr/local/include
ENV BOOST_LIBRARYDIR=/usr/local/lib

# Set JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# Set compiler flags to reduce warnings and potentially speed up the build
ENV CXXFLAGS="-Wno-deprecated-declarations -Wno-unused-result -std=c++20"

# Install Blight for embedding compile commands in binaries
# Blight is a crucial tool for our build process, allowing us to embed compile commands into the binaries
RUN echo "Installing Blight for embedding compile commands..." && \
    pip3 install --no-cache-dir git+https://github.com/trailofbits/blight@kumarak/embed_compile_command -v && \
    echo "Blight installation completed successfully."

# Set up Blight configuration
# Create necessary directories and set environment variables
RUN mkdir -p /workspace && \
    touch /workspace/blight_journal.jsonl && \
    touch /workspace/blight_record.jsonl
ENV BLIGHT_ACTIONS=Demo:SkipStrip:Record
ENV BLIGHT_JOURNAL_PATH=/workspace/blight_journal.jsonl
ENV BLIGHT_ACTION_RECORD="output=/workspace/blight_record.jsonl"

# Check Blight installation and run a simple test
RUN echo "Checking Blight installation..." && \
    pip3 list | grep blight && \
    which blight-exec || echo "blight-exec not found" && \
    which blight-compile || echo "blight-compile not found" && \
    blight-exec --help || echo "blight-exec --help failed" && \
    echo "Running Blight test..." && \
    blight-exec --guess-wrapped --swizzle-path --action Demo -- cc -v || echo "Blight test failed, but continuing build"

# Check Blight installation directory
RUN echo "Checking Blight installation directory:" && \
    ls -la /usr/local/bin/blight* || echo "No blight executables found in /usr/local/bin"

# Check Python path
RUN echo "Checking Python path:" && \
    python3 -c "import sys; print('\n'.join(sys.path))"

# Set the working directory for our project
WORKDIR /workspace

# Clone the Pastel repository from GitHub
# We use --depth 1 to create a shallow clone, which is faster and uses less space
RUN echo "Cloning the Pastel repository..." && \
    git clone --depth 1 https://github.com/pastelnetwork/pastel.git && \
    echo "Cloning completed successfully."

# Download and extract the Multiplier tool suite
# Multiplier is essential for our static analysis tasks
RUN echo "Downloading and extracting Multiplier release..." && \
    wget https://github.com/trailofbits/multiplier/releases/download/770d235/multiplier-770d235.tar.xz && \
    mkdir -p /opt/multiplier && \
    tar -xf multiplier-770d235.tar.xz -C /opt/multiplier && \
    rm multiplier-770d235.tar.xz && \
    echo "Multiplier extraction completed successfully."

# Set the working directory to the cloned repository
WORKDIR /workspace/pastel

# Capture environment variables to a file for later use
# This is important for preserving the build environment for our analysis tools
RUN echo "Capturing environment variables..." && \
    env > env_vars.txt && \
    echo "Environment variables saved successfully." && \
    echo "The environment variables file (env_vars.txt) is located at /workspace/pastel/env_vars.txt. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/env_vars.txt /path/on/host/env_vars.txt"

# Build the project using Blight and Bear to generate compile_commands.json
# This step is crucial for creating a comprehensive compilation database
RUN echo "Building the project with Blight and Bear..." && \
    echo "Checking build environment:" && \
    which ar && \
    which ranlib && \
    which ld && \
    echo "Building without Blight first:" && \
    ./build.sh -j$(nproc) || (echo "Build failed without Blight" && exit 1) && \
    echo "Now building with Blight:" && \
    BLIGHT_LOG_LEVEL=DEBUG blight-exec --guess-wrapped --swizzle-path -- bear -- ./build.sh -j$(nproc) && \
    echo "Project build and compile_commands.json generation completed successfully." && \
    echo "The compile_commands.json file is located at /workspace/pastel/compile_commands.json. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/compile_commands.json /path/on/host/compile_commands.json"

# If the build fails, try without Blight
RUN if [ ! -f compile_commands.json ]; then \
        echo "Build with Blight failed, trying without Blight..." && \
        bear -- ./build.sh -j$(nproc) && \
        echo "Build without Blight completed successfully."; \
    fi

# Configure Blight to embed compile commands into the build artifacts
# This step enhances our binaries with valuable compilation information
RUN echo "Embedding compile commands using Blight..." && \
    mkdir -p /tmp/commands && \
    BLIGHT_ACTION_EMBEDCOMMANDS="output=/tmp/commands" \
    BOOST_ROOT=/usr/local \
    BOOST_INCLUDEDIR=/usr/local/include \
    BOOST_LIBRARYDIR=/usr/local/lib \
    blight-exec --guess-wrapped --swizzle-path --action EmbedCommands -- ./build.sh -j$(nproc) && \
    echo "Compile commands embedded successfully." && \
    echo "The embedded compile commands are stored in binary files in the /tmp/commands directory. To extract this directory from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/tmp/commands /path/on/host/embedded_commands"

# Determine and set Clang resource directories for mx-index
# This ensures our analysis tools have access to the correct system headers and libraries
RUN echo "Setting up Clang resource directories..." && \
    CLANG_RESOURCE_DIR=$(clang -print-resource-dir) && \
    INCLUDE_DIRS=$(clang -E -x c++ - -v < /dev/null 2>&1 | grep -A 10 '#include <...> search starts here:' | tail -n +2 | sed -e '/^End/d' | tr -d ' ' | tr '\n' ':') && \
    echo "LIBRARY_PATH=$CLANG_RESOURCE_DIR" >> env_vars.txt && \
    echo "CPATH=\"$CLANG_RESOURCE_DIR/include:$INCLUDE_DIRS\"" >> env_vars.txt && \
    echo "CPPFLAGS=\"-nostdinc -nobuiltininc\"" >> env_vars.txt && \
    echo "Clang resource directories set successfully." && \
    echo "The updated env_vars.txt file with Clang resource directories is located at /workspace/pastel/env_vars.txt. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/env_vars.txt /path/on/host/updated_env_vars.txt"

# Index the project using mx-index
# This creates a comprehensive index of our codebase for further analysis
RUN echo "Indexing the project using mx-index..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-index \
    --db pastel_index.db \
    --target compile_commands.json \
    --workspace workspace \
    --env env_vars.txt \
    --show_progress && \
    echo "Indexing completed successfully." && \
    echo "The pastel_index.db file is located at /workspace/pastel/pastel_index.db. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/pastel_index.db /path/on/host/pastel_index.db"

# Run mx-find-divergent-candidates to find potential divergent representations
# This helps identify potential issues in type representations across the codebase
RUN echo "Running mx-find-divergent-candidates..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-find-divergent-candidates \
    --db pastel_index.db \
    --show_locations > divergent_candidates.txt && \
    echo "Divergent candidates analysis completed successfully." && \
    echo "The divergent_candidates.txt file is located at /workspace/pastel/divergent_candidates.txt. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/divergent_candidates.txt /path/on/host/divergent_candidates.txt"

# Run mx-find-symbol to search for specific symbols, example for 'log'
# This demonstrates how to search for specific symbols in our codebase
RUN echo "Searching for the symbol 'log' using mx-find-symbol..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-find-symbol \
    --db pastel_index.db \
    --name log > log_symbol_search.txt && \
    echo "Symbol search completed successfully." && \
    echo "The log_symbol_search.txt file is located at /workspace/pastel/log_symbol_search.txt. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/log_symbol_search.txt /path/on/host/log_symbol_search.txt"

# Run mx-find-sketchy-casts to find sketchy casts in the codebase
# This helps identify potentially dangerous type casts in our code
RUN echo "Running mx-find-sketchy-casts to identify sketchy casts..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-find-sketchy-casts \
    --db pastel_index.db \
    --show_explicit > sketchy_casts.txt && \
    echo "Sketchy casts analysis completed successfully." && \
    echo "The sketchy_casts.txt file is located at /workspace/pastel/sketchy_casts.txt. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/sketchy_casts.txt /path/on/host/sketchy_casts.txt"

# Generate a call graph for a specific function
# Note: ENTITY_ID and FROM_ENTITY_ID need to be replaced with actual values obtained from previous analysis steps
RUN echo "Generating call graph for the specified function..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-print-call-graph \
    --db pastel_index.db \
    --entity_id ENTITY_ID \
    --reachable_from_entity_id FROM_ENTITY_ID \
    > call_graph.dot && \
    echo "Call graph generation completed successfully." && \
    echo "The call_graph.dot file is located at /workspace/pastel/call_graph.dot. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/call_graph.dot /path/on/host/call_graph.dot" && \
    echo "To visualize the call graph, you can use Graphviz on your Ubuntu host machine with the command: dot -Tpng -o call_graph.png call_graph.dot"

# Generate a reference graph for a specific function
# Note: ENTITY_ID needs to be replaced with an actual value obtained from previous analysis steps
RUN echo "Generating reference graph for the specified function..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-print-reference-graph \
    --db pastel_index.db \
    --entity_id ENTITY_ID \
    --length 3 \
    > reference_graph.dot && \
    echo "Reference graph generation completed successfully." && \
    echo "The reference_graph.dot file is located at /workspace/pastel/reference_graph.dot. To extract it from the Docker image, use the following command on your Ubuntu host machine:" && \
    echo "docker cp <container_id>:/workspace/pastel/reference_graph.dot /path/on/host/reference_graph.dot" && \
    echo "To visualize the reference graph, you can use Graphviz on your Ubuntu host machine with the command: dot -Tpng -o reference_graph.png reference_graph.dot"

# Remove the workspace directory to clean up temporary files
RUN echo "Cleaning up workspace directory..." && \
    rm -rf workspace && \
    echo "Workspace cleanup completed successfully."

# By default, start an interactive shell for further inspection
# This allows users to explore the built environment and analysis results
CMD ["/bin/bash"]