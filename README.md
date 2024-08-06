# Pastel Analysis Dockerfile

## Overview

This Dockerfile sets up a comprehensive environment for analyzing the Pastel blockchain project. It combines various tools and techniques to provide deep insights into the codebase, including static analysis, symbol searching, and call graph generation. The primary goal is to facilitate thorough code examination, identify potential issues, and generate visual representations of code structure and dependencies.

Key features of this analysis environment include:

1. Automated build process for the Pastel project
2. Integration of Blight for embedding compile commands
3. Utilization of the Multiplier tool suite for advanced code analysis
4. Generation of various analysis artifacts such as divergent candidates, symbol searches, and sketchy casts
5. Creation of call graphs and reference graphs for visualizing code relationships

This setup is particularly useful for developers, security researchers, and code auditors who need to perform in-depth analysis of the Pastel codebase. It provides a consistent, reproducible environment that captures compilation details and enables sophisticated static analysis techniques.

## Detailed Breakdown of Dockerfile Steps

### 1. Base Image and Environment Setup

```dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
```

- Uses Ubuntu 22.04 as the base image for stability and compatibility
- Sets the `DEBIAN_FRONTEND` to non-interactive to prevent prompts during package installation

### 2. Installing Required Packages

```dockerfile
RUN echo "Starting installation of necessary packages including Clang and RocksDB..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        # ... (list of packages)
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "Package installation completed successfully."
```

- Installs a comprehensive set of development tools and libraries
- Includes Clang for compilation, RocksDB for database operations, and various utilities
- Uses `--no-install-recommends` to minimize image size
- Cleans up apt cache to reduce image size

### 3. Installing Boost

```dockerfile
RUN wget https://boostorg.jfrog.io/artifactory/main/release/1.82.0/source/boost_1_82_0.tar.gz && \
    tar -xzf boost_1_82_0.tar.gz && \
    cd boost_1_82_0 && \
    ./bootstrap.sh --prefix=/usr/local && \
    ./b2 install && \
    cd .. && \
    rm -rf boost_1_82_0 boost_1_82_0.tar.gz
```

- Downloads and installs Boost 1.82.0 from source
- Configures Boost to install in `/usr/local`
- Removes source files after installation to save space

### 4. Setting Environment Variables

```dockerfile
ENV BOOST_ROOT=/usr/local
ENV BOOST_INCLUDEDIR=/usr/local/include
ENV BOOST_LIBRARYDIR=/usr/local/lib
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV CXXFLAGS="-Wno-deprecated-declarations -Wno-unused-result -std=c++20"
```

- Sets up Boost-related environment variables
- Configures Java home directory
- Sets compiler flags to reduce warnings and use C++20 standard

### 5. Installing Blight

```dockerfile
RUN echo "Installing Blight for embedding compile commands..." && \
    pip3 install --no-cache-dir git+https://github.com/trailofbits/blight@kumarak/embed_compile_command -v && \
    echo "Blight installation completed successfully."
```

- Installs Blight from a specific GitHub branch
- Blight is used to embed compile commands into binaries

### 6. Configuring Blight

```dockerfile
RUN mkdir -p /workspace && \
    touch /workspace/blight_journal.jsonl && \
    touch /workspace/blight_record.jsonl
ENV BLIGHT_ACTIONS=Demo:SkipStrip:Record
ENV BLIGHT_JOURNAL_PATH=/workspace/blight_journal.jsonl
ENV BLIGHT_ACTION_RECORD="output=/workspace/blight_record.jsonl"
```

- Sets up necessary directories and files for Blight
- Configures Blight actions and output paths

### 7. Checking Blight Installation

```dockerfile
RUN echo "Checking Blight installation..." && \
    pip3 list | grep blight && \
    which blight-exec || echo "blight-exec not found" && \
    which blight-compile || echo "blight-compile not found" && \
    blight-exec --help || echo "blight-exec --help failed" && \
    echo "Running Blight test..." && \
    blight-exec --guess-wrapped --swizzle-path --action Demo -- cc -v || echo "Blight test failed, but continuing build"
```

- Verifies Blight installation and runs a simple test
- Continues the build process even if the test fails

### 8. Cloning Pastel Repository

```dockerfile
RUN echo "Cloning the Pastel repository..." && \
    git clone --depth 1 https://github.com/pastelnetwork/pastel.git && \
    echo "Cloning completed successfully."
```

- Clones the Pastel repository from GitHub
- Uses a shallow clone (`--depth 1`) for faster download and less disk usage

### 9. Installing Multiplier Tool Suite

```dockerfile
RUN echo "Downloading and extracting Multiplier release..." && \
    wget https://github.com/trailofbits/multiplier/releases/download/770d235/multiplier-770d235.tar.xz && \
    mkdir -p /opt/multiplier && \
    tar -xf multiplier-770d235.tar.xz -C /opt/multiplier && \
    rm multiplier-770d235.tar.xz && \
    echo "Multiplier extraction completed successfully."
```

- Downloads and extracts the Multiplier tool suite
- Multiplier is used for various static analysis tasks

### 10. Capturing Environment Variables

```dockerfile
RUN echo "Capturing environment variables..." && \
    env > env_vars.txt && \
    echo "Environment variables saved successfully."
```

- Saves current environment variables to a file for later use

### 11. Building the Pastel Project

```dockerfile
RUN echo "Building the project with Blight and Bear..." && \
    echo "Checking build environment:" && \
    which ar && \
    which ranlib && \
    which ld && \
    echo "Building without Blight first:" && \
    ./build.sh -j$(nproc) || (echo "Build failed without Blight" && exit 1) && \
    echo "Now building with Blight:" && \
    BLIGHT_LOG_LEVEL=DEBUG blight-exec --guess-wrapped --swizzle-path -- bear -- ./build.sh -j$(nproc) && \
    echo "Project build and compile_commands.json generation completed successfully."
```

- Builds the Pastel project using Blight and Bear
- Generates `compile_commands.json` for later analysis
- Attempts a build without Blight first, then with Blight if successful

### 12. Embedding Compile Commands

```dockerfile
RUN echo "Embedding compile commands using Blight..." && \
    mkdir -p /tmp/commands && \
    BLIGHT_ACTION_EMBEDCOMMANDS="output=/tmp/commands" \
    BOOST_ROOT=/usr/local \
    BOOST_INCLUDEDIR=/usr/local/include \
    BOOST_LIBRARYDIR=/usr/local/lib \
    blight-exec --guess-wrapped --swizzle-path --action EmbedCommands -- ./build.sh -j$(nproc) && \
    echo "Compile commands embedded successfully."
```

- Uses Blight to embed compile commands into build artifacts
- Stores embedded commands in `/tmp/commands`

### 13. Setting Up Clang Resource Directories

```dockerfile
RUN echo "Setting up Clang resource directories..." && \
    CLANG_RESOURCE_DIR=$(clang -print-resource-dir) && \
    INCLUDE_DIRS=$(clang -E -x c++ - -v < /dev/null 2>&1 | grep -A 10 '#include <...> search starts here:' | tail -n +2 | sed -e '/^End/d' | tr -d ' ' | tr '\n' ':') && \
    echo "LIBRARY_PATH=$CLANG_RESOURCE_DIR" >> env_vars.txt && \
    echo "CPATH=\"$CLANG_RESOURCE_DIR/include:$INCLUDE_DIRS\"" >> env_vars.txt && \
    echo "CPPFLAGS=\"-nostdinc -nobuiltininc\"" >> env_vars.txt && \
    echo "Clang resource directories set successfully."
```

- Determines and sets Clang resource directories
- Updates `env_vars.txt` with Clang-specific environment variables

### 14. Indexing the Project

```dockerfile
RUN echo "Indexing the project using mx-index..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-index \
    --db pastel_index.db \
    --target compile_commands.json \
    --workspace workspace \
    --env env_vars.txt \
    --show_progress && \
    echo "Indexing completed successfully."
```

- Uses `mx-index` from the Multiplier suite to index the project
- Creates `pastel_index.db` for further analysis

### 15. Running Various Analysis Tools

```dockerfile
RUN echo "Running mx-find-divergent-candidates..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-find-divergent-candidates \
    --db pastel_index.db \
    --show_locations > divergent_candidates.txt

RUN echo "Searching for the symbol 'log' using mx-find-symbol..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-find-symbol \
    --db pastel_index.db \
    --name log > log_symbol_search.txt

RUN echo "Running mx-find-sketchy-casts to identify sketchy casts..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-find-sketchy-casts \
    --db pastel_index.db \
    --show_explicit > sketchy_casts.txt
```

- Runs various analysis tools from the Multiplier suite:
  - `mx-find-divergent-candidates`: Finds potential divergent representations
  - `mx-find-symbol`: Searches for specific symbols (e.g., 'log')
  - `mx-find-sketchy-casts`: Identifies potentially dangerous type casts
- Outputs results to separate text files

### 16. Generating Call and Reference Graphs

```dockerfile
RUN echo "Generating call graph for the specified function..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-print-call-graph \
    --db pastel_index.db \
    --entity_id ENTITY_ID \
    --reachable_from_entity_id FROM_ENTITY_ID \
    > call_graph.dot

RUN echo "Generating reference graph for the specified function..." && \
    /opt/multiplier/multiplier-770d235/bin/mx-print-reference-graph \
    --db pastel_index.db \
    --entity_id ENTITY_ID \
    --length 3 \
    > reference_graph.dot
```

- Generates call graph and reference graph for specified functions
- Outputs graphs in DOT format for later visualization
- Note: `ENTITY_ID` and `FROM_ENTITY_ID` need to be replaced with actual values

### 17. Cleanup and Final Configuration

```dockerfile
RUN echo "Cleaning up workspace directory..." && \
    rm -rf workspace && \
    echo "Workspace cleanup completed successfully."

CMD ["/bin/bash"]
```

- Removes temporary workspace directory
- Sets the default command to start an interactive bash shell

## Usage Instructions

### Building the Docker Image

To build the Docker image, use the following command:

```bash
sudo docker build --progress=plain -t pastel_analysis . > build_log.txt 2>&1
```

This command builds the image with the tag `pastel_analysis` and saves the build log to `build_log.txt`.

### Running the Analysis

1. Start the Docker container:

   ```bash
   sudo docker run -it pastel_analysis
   ```

   This command runs the container interactively, allowing you to use the shell inside the container.

2. Explore the analysis results:
   Once inside the container, you can view the analysis output files:

   ```bash
   cat divergent_candidates.txt
   cat log_symbol_search.txt
   cat sketchy_casts.txt
   ```

3. Generate visualizations (optional):
   For the DOT files (call graph and reference graph), you can generate visual representations:

   ```bash
   dot -Tpng call_graph.dot -o call_graph.png
   dot -Tpng reference_graph.dot -o reference_graph.png
   ```

4. Copy files out of the container (optional):
   To examine results on your host machine, first exit the container (type `exit`), then use:

   ```bash
   container_id=$(sudo docker ps -a | grep pastel_analysis | awk '{print $1}')
   sudo docker cp $container_id:/workspace/pastel/divergent_candidates.txt .
   sudo docker cp $container_id:/workspace/pastel/log_symbol_search.txt .
   sudo docker cp $container_id:/workspace/pastel/sketchy_casts.txt .
   sudo docker cp $container_id:/workspace/pastel/call_graph.dot .
   sudo docker cp $container_id:/workspace/pastel/reference_graph.dot .
   ```

   This one-liner automates the process of finding the container ID and copying the files.

## Customization

To generate call graphs or reference graphs for specific functions, replace the `ENTITY_ID` and `FROM_ENTITY_ID` placeholders in the Dockerfile with actual values. These values can be obtained by querying the `pastel_index.db` database using the Multiplier tools.

## Conclusion

This Dockerfile sets up a powerful environment for analyzing the Pastel blockchain project. By combining various tools and techniques, it provides deep insights into the codebase, helping developers and researchers identify potential issues and understand the project structure more thoroughly.
