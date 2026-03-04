# Setting Up a Spark Cluster Manually

> **Stack:** Ubuntu 22.04 · Java 17 · Hadoop 3.4.2 · Spark 4.1.1  
> **Cluster layout:** 1 Master node + 2–3 Worker nodes

---

## Table of Contents

1. [Overview & Cluster Layout](#overview--cluster-layout)
2. [Steps for ALL Nodes](#steps-for-all-nodes)
   - [Step 1 — System Update & Package Installation](#step-1--system-update--package-installation)
   - [Step 2 — Install Java (OpenJDK 17)](#step-2--install-java-openjdk-17)
   - [Step 3 — Register Cluster Nodes in `/etc/hosts`](#step-3--register-cluster-nodes-in-etchosts)
   - [Step 4 — Download & Install Hadoop](#step-4--download--install-hadoop)
   - [Step 5 — Download & Install Spark](#step-5--download--install-spark)
   - [Step 6 — Set Environment Variables](#step-6--set-environment-variables)
3. [Master Node Setup](#master-node-setup)
   - [Step 7 — Configure Hadoop (Master)](#step-7--configure-hadoop-master)
   - [Step 8 — Format & Start HDFS](#step-8--format--start-hdfs)
   - [Step 9 — Start YARN & Job History Server](#step-9--start-yarn--job-history-server)
   - [Step 10 — Configure & Start Spark Master](#step-10--configure--start-spark-master)
4. [Worker Node Setup](#worker-node-setup)
   - [Step 11 — Configure Hadoop (Worker)](#step-11--configure-hadoop-worker)
   - [Step 12 — Start HDFS DataNode](#step-12--start-hdfs-datanode)
   - [Step 13 — Start YARN NodeManager](#step-13--start-yarn-nodemanager)
   - [Step 14 — Configure & Start Spark Worker](#step-14--configure--start-spark-worker)
5. [Verification Checklist](#verification-checklist)

---

## Overview & Cluster Layout

You will provision **3 VMs** in total: one master and two workers. Before you start, boot all three VMs and note down their IP addresses — you'll need them shortly.

| Role | Hostname (example) | IP (example) |
|---|---|---|
| Master | `vm-1` | `192.168.2.10` |
| Worker 1 | `vm-2` | `192.168.2.11` |
| Worker 2 | `vm-3` | `192.168.2.12` |

> Replace the IPs and hostnames in the examples below with the actual values from your VMs. To find a VM's IP and hostname, run:
> ```bash
> hostname -I   # shows IP address(es)
> hostname      # shows current hostname
> ```

The steps are organized into two groups:
- **Steps 1–6** are identical on every node — do these on the master and all workers.
- **Steps 7–10** are for the master only.
- **Steps 11–14** are for each worker (repeat per worker).

---

## Steps for ALL Nodes

> ⚙️ **Run the following steps on the master AND every worker node before proceeding.**

---

### Step 1 — System Update & Package Installation

```bash
sudo apt-get update -y && sudo apt-get upgrade -y

sudo apt-get install -y \
  python3-pip \
  python3-dev \
  build-essential \
  tmux \
  apt-transport-https \
  ca-certificates \
  curl \
  software-properties-common
```

---

### Step 2 — Install Java (OpenJDK 17)

Hadoop and Spark both require Java. Install the headless (server-side) variant of OpenJDK 17.

```bash
sudo apt-get install -y openjdk-17-jdk-headless
```

Verify:

```bash
java -version
# Expected output: openjdk version "17.x.x" ...
```

---

### Step 3 — Register Cluster Nodes in `/etc/hosts`

Each node needs to be able to resolve the other nodes by hostname. You do this by manually adding an entry for each VM in `/etc/hosts`.

```bash
sudo nano /etc/hosts
```

Add a line for each node in your cluster (replace with your actual IPs and hostnames):

```
192.168.2.10  vm-1
192.168.2.11  vm-2
192.168.2.12  vm-3
```

> **Note:** Use the actual IP addresses and hostnames you collected before starting. Run `hostname -I` and `hostname` on each VM to get these values. You do not need to change the hostnames — just register them here so nodes can find each other.

Save and exit (`Ctrl+X`, `Y`, `Enter` in nano). Verify name resolution works:

```bash
ping vm-2 -c 2   # from the master, should reach worker 1
ping vm-1 -c 2   # from a worker, should reach the master
```

---

### Step 4 — Download & Install Hadoop

```bash
# Download
wget -nv https://dlcdn.apache.org/hadoop/common/hadoop-3.4.2/hadoop-3.4.2.tar.gz -P ~/

# Extract and rename
tar -zxf ~/hadoop-3.4.2.tar.gz -C ~/
mv ~/hadoop-3.4.2 ~/hadoop

# Set ownership
chown -R ubuntu:ubuntu ~/hadoop

# Remove the archive
rm -f ~/hadoop-3.4.2.tar.gz
```

---

### Step 5 — Download & Install Spark

```bash
# Download (pre-built for Hadoop 3)
wget -nv https://dlcdn.apache.org/spark/spark-4.1.1/spark-4.1.1-bin-hadoop3.tgz -P ~/

# Extract and rename
tar -zxf ~/spark-4.1.1-bin-hadoop3.tgz -C ~/
mv ~/spark-4.1.1-bin-hadoop3 ~/spark

# Set ownership
chown -R ubuntu:ubuntu ~/spark

# Remove the archive
rm -f ~/spark-4.1.1-bin-hadoop3.tgz
```

---

### Step 6 — Set Environment Variables

Add the required paths to your shell profile and to Hadoop's own environment config.

```bash
# Tell Hadoop's daemons where Java lives
echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> ~/hadoop/etc/hadoop/hadoop-env.sh
echo "export HADOOP_HOME=/home/ubuntu/hadoop"               >> ~/hadoop/etc/hadoop/hadoop-env.sh

# Add all three to your shell profile so they persist across sessions
echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> ~/.bashrc
echo "export HADOOP_HOME=/home/ubuntu/hadoop"               >> ~/.bashrc
echo "export SPARK_HOME=/home/ubuntu/spark"                 >> ~/.bashrc

# Apply to your current session
source ~/.bashrc
```

Verify:

```bash
echo $JAVA_HOME    # /usr/lib/jvm/java-17-openjdk-amd64
echo $HADOOP_HOME  # /home/ubuntu/hadoop
echo $SPARK_HOME   # /home/ubuntu/spark
```

---

## Master Node Setup

> 🖥️ **Run Steps 7–10 on the master node only.**

---

### Step 7 — Configure Hadoop (Master)

Hadoop uses two XML config files to know where the NameNode lives and how to store data.

#### `core-site.xml` — Default Filesystem

This tells all Hadoop components to use HDFS, served from this master node on port 9000. We bind to `0.0.0.0` so the master accepts connections on all its network interfaces.

Open the file:

```bash
nano ~/hadoop/etc/hadoop/core-site.xml
```

Replace the empty `<configuration>` tags with:

```xml
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://0.0.0.0:9000</value>
  </property>
</configuration>
```

#### `hdfs-site.xml` — HDFS Settings

This sets where the NameNode stores its metadata locally, and how many times each data block is replicated across DataNodes.

```bash
nano ~/hadoop/etc/hadoop/hdfs-site.xml
```

```xml
<configuration>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>/home/ubuntu/hdfs-data</value>
  </property>
  <property>
    <name>dfs.replication</name>
    <value>2</value>
  </property>
</configuration>
```

> **Replication factor:** Set `dfs.replication` to the number of worker nodes you have (e.g. `2` for two workers). This means each file block will be stored on 2 different DataNodes. Do not set it higher than your number of workers.

---

### Step 8 — Format & Start HDFS

#### Format the NameNode

> ⚠️ **Do this exactly once.** Formatting initializes the HDFS metadata directory. Running it again on a live cluster will destroy all stored data.

```bash
~/hadoop/bin/hdfs namenode -format
```

#### Start the NameNode and DataNode

```bash
~/hadoop/bin/hdfs --daemon start namenode
~/hadoop/bin/hdfs --daemon start datanode
```

Verify HDFS is up:

```bash
jps
# Should include: NameNode, DataNode

~/hadoop/bin/hdfs dfsadmin -report
# Should show the NameNode as active
```

The HDFS Web UI is also available at `http://<MASTER_IP>:9870`.

---

### Step 9 — Start YARN & Job History Server

YARN manages cluster resources and job scheduling. The History Server stores logs of completed jobs.

```bash
~/hadoop/bin/yarn --daemon start resourcemanager
~/hadoop/bin/yarn --daemon start nodemanager
~/hadoop/bin/yarn --daemon start proxyserver

~/hadoop/bin/mapred --daemon start historyserver
```

Verify:

```bash
jps
# Should now also include: ResourceManager, NodeManager, JobHistoryServer

~/hadoop/bin/yarn node -list
# Lists the master as an active node
```

---

### Step 10 — Configure & Start Spark Master

#### Configure Spark event logging

Tell Spark to log job events to HDFS so the History Server can display them.

```bash
echo "spark.eventLog.enabled           true"                              >> ~/spark/conf/spark-defaults.conf
echo "spark.eventLog.compress          false"                             >> ~/spark/conf/spark-defaults.conf
echo "spark.eventLog.dir               hdfs://localhost:9000/spark-logs"  >> ~/spark/conf/spark-defaults.conf
echo "spark.history.fs.logDirectory    hdfs://localhost:9000/spark-logs"  >> ~/spark/conf/spark-defaults.conf
```

Create the log directory in HDFS:

```bash
~/hadoop/bin/hdfs dfs -mkdir -p /spark-logs
```

#### Start the Spark Master

```bash
~/spark/sbin/start-master.sh
```

Verify:

```bash
jps
# Should now also include: Master

# Check the Spark master log for the master URL
cat ~/spark/logs/spark-ubuntu-org.apache.spark.deploy.master.Master-*.out | grep "spark://"
```

> 📌 **Note your Spark Master URL** — it looks like `spark://<MASTER_IP>:7077`. You will need this when starting each worker in Step 14.

The Spark Master Web UI is available at `http://<MASTER_IP>:8080`.

---

## Worker Node Setup

> 👷 **Run Steps 11–14 on each worker node. Repeat for every worker you add.**

---

### Step 11 — Configure Hadoop (Worker)

Workers need to point at the **master's IP** to find the HDFS NameNode. This is the key difference from the master configuration.

#### `core-site.xml`

```bash
nano ~/hadoop/etc/hadoop/core-site.xml
```

```xml
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://192.168.2.10:9000</value>   <!-- replace with your actual master IP -->
  </property>
</configuration>
```

#### `hdfs-site.xml`

```bash
nano ~/hadoop/etc/hadoop/hdfs-site.xml
```

```xml
<configuration>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>/home/ubuntu/hdfs-data</value>
  </property>
  <property>
    <name>dfs.replication</name>
    <value>2</value>
  </property>
</configuration>
```

> **Key difference from the master:** `fs.defaultFS` points to the master's IP address, not `0.0.0.0`. Workers connect to the NameNode running on the master — they do not run their own.

---

### Step 12 — Start HDFS DataNode

Workers store data blocks as DataNodes. They do **not** run a NameNode.

> ⚠️ Do **not** run `hdfs namenode -format` on a worker. Only the master does this, and only once.

```bash
~/hadoop/bin/hdfs --daemon start datanode
```

Verify the DataNode started and registered with the master:

```bash
jps
# Should include: DataNode

# From the master, confirm this worker appears:
~/hadoop/bin/hdfs dfsadmin -report
```

---

### Step 13 — Start YARN NodeManager

Workers run a NodeManager to offer their compute resources to YARN. They do **not** run a ResourceManager.

```bash
~/hadoop/bin/yarn --daemon start nodemanager
```

Verify:

```bash
jps
# Should include: NodeManager

# From the master:
~/hadoop/bin/yarn node -list
# This worker should appear in the list
```

---

### Step 14 — Configure & Start Spark Worker

#### Configure Spark event logging

Use the same configuration as the master so all nodes log to the same HDFS directory.

```bash
echo "spark.eventLog.enabled           true"                              >> ~/spark/conf/spark-defaults.conf
echo "spark.eventLog.compress          false"                             >> ~/spark/conf/spark-defaults.conf
echo "spark.eventLog.dir               hdfs://localhost:9000/spark-logs"  >> ~/spark/conf/spark-defaults.conf
echo "spark.history.fs.logDirectory    hdfs://localhost:9000/spark-logs"  >> ~/spark/conf/spark-defaults.conf
```

#### Join the Spark cluster

Register this worker with the Spark Master using the URL you noted in Step 10.

```bash
# Replace with your actual master IP
~/spark/sbin/start-worker.sh spark://192.168.2.10:7077
```

Verify:

```bash
jps
# Should include: Worker
```

Then check the **Spark Master Web UI** at `http://<MASTER_IP>:8080` — this worker should appear in the **Workers** section with status `ALIVE`.

---

## Verification Checklist

### Expected processes per node (`jps`)

| Process | Master | Worker |
|---|:---:|:---:|
| NameNode | ✅ | ❌ |
| DataNode | ✅ | ✅ |
| SecondaryNameNode | ✅ | ❌ |
| ResourceManager | ✅ | ❌ |
| NodeManager | ✅ | ✅ |
| JobHistoryServer | ✅ | ❌ |
| Master *(Spark)* | ✅ | ❌ |
| Worker *(Spark)* | ❌ | ✅ |

### Web UIs

| Interface | URL |
|---|---|
| HDFS NameNode | `http://<MASTER_IP>:9870` |
| YARN ResourceManager | `http://<MASTER_IP>:8088` |
| MapReduce History Server | `http://<MASTER_IP>:19888` |
| Spark Master | `http://<MASTER_IP>:8080` |