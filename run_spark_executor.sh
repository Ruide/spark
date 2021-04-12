#!/bin/bash
set -e

BLUE='\033[1;34m'
NC='\033[0m'
occlum_glibc=/opt/occlum/glibc/lib/
export SGX_MODE=HW
# export OCCLUM_LOG_LEVEL=warn
# export SGX_MODE=SIM
# export OCCLUM_LOG_LEVEL=off, error, warn, debug, info, trace


init_instance() {
    # Init Occlum instance
    SPARK_LOG_PREFIX="/host/spark-executor-${id}"
    log="${SPARK_LOG_PREFIX}.log"
    out="./spark-executor-${id}.out"

    rm -rf occlum_instance_executor && mkdir occlum_instance_executor
    cd occlum_instance_executor
    occlum init
    new_json="$(jq '.resource_limits.user_space_size = "8000MB" |
        .resource_limits.kernel_space_heap_size="512MB" |
        .resource_limits.kernel_space_stack_size="8MB" |
        .resource_limits.max_num_of_threads = 512 |
        .process.default_stack_size = "256MB" |
        .process.default_heap_size = "2048MB" |
        .process.default_mmap_size = "4096MB" |
        .entry_points = [ "/usr/lib/jvm/java-11-alibaba-dragonwell/jre/bin" ] |
        .env.default = [ "LD_LIBRARY_PATH=/usr/lib/jvm/java-11-alibaba-dragonwell/jre/lib/server:/usr/lib/jvm/java-11-alibaba-dragonwell/jre/lib:/usr/lib/jvm/java-11-alibaba-dragonwell/jre/../lib","SPARK_USER=root","SPARK_HOME=/bin","USER=root", "SPARK_IDENT_STRING=root", "SPARK_SCALA_VERSION=2.12","SPARK_CONF_DIR=/bin/conf" ] |
        .env.untrusted = [ "SPARK_EXECUTOR_DIRS","SPARK_LAUNCH_WITH_SCALA","SPARK_LOG_URL_STDERR","SPARK_LOG_URL_STDOUT" ] ' Occlum.json)" && \
    echo "${new_json}" > Occlum.json
}
    #   "_JAVA_OPTIONS=-Djdk.lang.Process.launchMechanism=POSIX_SPAWN"
    #   "SPARK_ENV_LOADED=1",
    #   "SPARK_ENV_SH=spark-env.sh",
    #   "MASTER=spark://localhost:7077",
    #   "SPARK_WORKER_WEBUI_PORT=8081",
    #   "WORKER_NUM=1",
    #   "WEBUI_PORT=8081",
    #   "SPARK_IDENT_STRING=root",
    #   "SPARK_PRINT_LAUNCH_COMMAND=1",
    #   "SPARK_LOG_DIR=/bin/logs",
    #   "TEST_LOG_DIR=0",
    #   "SPARK_PID_DIR=/tmp",
    #   "SPARK_NICENESS=0"

build_spark() {
    # Copy JVM and class file into Occlum instance and build
    mkdir -p image/usr/lib/jvm
    cp -r /opt/occlum/toolchains/jvm/java-11-alibaba-dragonwell image/usr/lib/jvm
    sed -i '10 a grant codeBase "file:/bin/-" {' image/usr/lib/jvm/java-11-alibaba-dragonwell/lib/security/default.policy
    sed -i '11 a \ \ \ \ permission java.security.AllPermission;' image/usr/lib/jvm/java-11-alibaba-dragonwell/lib/security/default.policy
    sed -i '12 a };' image/usr/lib/jvm/java-11-alibaba-dragonwell/lib/security/default.policy
    cp /usr/local/occlum/x86_64-linux-musl/lib/libz.so.1 image/lib
    cp $occlum_glibc/libdl.so.2 image/$occlum_glibc
    cp $occlum_glibc/librt.so.1 image/$occlum_glibc
    cp $occlum_glibc/libm.so.6 image/$occlum_glibc
    cp $occlum_glibc/libnss_files.so.2 image/$occlum_glibc

    mkdir -p image/bin/conf
    mkdir -p image/bin/jars
    cp -rf ../assembly/target/scala-2.12/jars/* image/bin/jars
    cp -rf ../conf image/bin/conf
    cp -rf ../hosts image/etc/
    cp /etc/passwd image/etc/
    cp /etc/resolv.conf image/etc/
    cp /etc/timezone image/etc/
    occlum build
}

id=$([ -f "$pid" ] && echo $(wc -l < "$pid") || echo "0")

init_instance
build_spark

# echo -e "${BLUE}occlum run JVM executor ${NC}"
# echo -e "${BLUE}logfile=$log${NC}"

# occlum run "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" "-cp" "/bin/conf/:/bin/jars/*" "-Xmx1024M" "-Dspark.driver.port=40199" "-Djdk.lang.Process.launchMechanism=POSIX_SPAWN" "org.apache.spark.executor.CoarseGrainedExecutorBackend" "--driver-url" "spark://CoarseGrainedScheduler@7a11b1c24c2a:40199" "--executor-id" "0" "--hostname" "172.17.0.2" "--cores" "1" "--app-id" "app-20210329231456-0008" "--worker-url" "spark://Worker@172.17.0.2:32941"
# occlum run /usr/lib/jvm/java-11-alibaba-dragonwell/jre/bin/java \
# -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=0.0.0.0:5555 \
# -XX:-UseCompressedOops \
# -XX:ActiveProcessorCount=8 \
# -Djdk.lang.Process.launchMechanism=POSIX_SPAWN \
# -Dos.name=Linux \
# -Dlog.file=$log \
# -cp /bin/conf/:/bin/jars/* \
# -Xmx1g org.apache.spark.deploy.worker.Worker \
# --webui-port 8081 -c 1 -m 2g spark://localhost:7077

# -XX:+PrintGCDetails \
# You should use -XX:+UseCompressedOops if maximum heap size specified by -Xmx is less than 32G.
