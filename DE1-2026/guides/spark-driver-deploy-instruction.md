# Data Engineering: Spark Driver VM Setup Guide

> **Note:** This guide walks you through setting up a local driver VM to access the course Spark/HDFS cluster. It includes both *how* to do each step and *why* it’s necessary.

---

## 🚀 Overview: Architecture at a Glance

```text
Your Laptop
   |
   |  SSH + Port Forwarding
   v
Driver VM (Jupyter, PySpark)
   |
   |  Spark protocol
   v
Spark Master ── Workers ── HDFS
```

- **Driver VM (your VM)**: orchestrates computation, runs notebooks, communicates with the cluster.
- **Spark Cluster**: executes tasks in parallel and stores data in HDFS.
- **Web UIs**: Spark Master, HDFS, and application UIs, accessed via port forwarding.

> [!NOTE]
> Keep this diagram in mind — many common errors happen because students misunderstand where each component runs.

---

## Step 0: Driver VM Requirements

- Minimum: 2GB RAM, 1 CPU core (ssc.small)
- Recommended: 4GB RAM, 2 CPU cores for smoother Jupyter use (ssc.medium)
- Ensure Python 3.10+ and internet connectivity on the VM

---

## Step 1: Identify the Spark Master Private IP

> [!IMPORTANT]
> The cluster configuration may change for various reasons, so you should always use the **latest private IP** of the Spark master node.

You can fetch it using the following steps:

1. Open and log in to the project instances page: [https://east-1.cloud.snic.se/project/instances/](https://east-1.cloud.snic.se/project/instances/)
2. Apply a filter on the **Instance Name** using `SPARK-` to show only Spark cluster instances.
3. Look for the **head node** instance, typically named `SPARK-nnnn-headnode`, and note its **private IP address** (something like `192.168.x.y`).
4. Use this IP wherever `<MASTERNODE_PRIVATE_IP>` appears in your **SSH config** and **SparkSession** throughout the remainder of this guide.

---

## Step 2: SSH Port Forwarding (Accessing Web UIs)

### Why this is needed?
The Spark/HDFS cluster is **not public**. To access dashboards and the Spark application UI from your browser, we create a **secure SSH tunnel** from your machine to the cluster.

| Local Port | Destination | Purpose |
|------------|-------------|---------|
| 8080       | <MASTERNODE_PRIVATE_IP>:8080 | Spark Master Web UI |
| 9870       | <MASTERNODE_PRIVATE_IP>:9870 | HDFS NameNode Web UI |
| 8888       | localhost:8888     | Jupyter Notebook |
| 4040–4060 | localhost:4040–4060 | Spark application Web UIs |

> 4040–4060: each running Spark application gets a separate UI port.

---

### SSH Config Example (Unix / WSL)
Replace `130.238.x.y` with your VM’s floating IP and `~/.ssh/id_rsa` with your private key path:

```bash
Host 130.238.x.y
    User ubuntu
    IdentityFile ~/.ssh/id_rsa

    # Spark Master Web UI (replace with latest private IP)
    LocalForward 8080 <MASTERNODE_PRIVATE_IP>:8080
    
    # HDFS NameNode Web UI (replace with latest private IP)
    LocalForward 9870 <MASTERNODE_PRIVATE_IP>:9870
    
    # Jupyter Notebook
    LocalForward 8888 localhost:8888
    
    # Spark applications (if needed)
    LocalForward 4040 localhost:4040
    LocalForward 4041 localhost:4041
    LocalForward 4042 localhost:4042
    ...
```

---

### Tips & Diagnostics

* You may get a warning about an "UNPROTECTED PRIVATE KEY FILE!" - to fix this, change the permissions on your key file to 400. i.e.
  ```bash
  chmod 400 ~/.ssh/my_key.pem
  ```
* On Windows Subsystem for Linux (WSL), the key path is relative to the Linux filesystem (`/home/username/...`)
* Test the connection:
  ```bash
  ssh 130.238.x.y
  ```
* Open [http://localhost:8080](http://localhost:8080) and [http://localhost:9870](http://localhost:9870) to verify the Spark and HDFS web UIs.

---

## Step 3: Install Dependencies on the Driver VM

### Why install Spark locally?

Even though computations run on the cluster, the **driver process** uses PySpark locally to:

* Build the DAG
* Submit tasks to the cluster
* Collect results for analysis

---

### Commands

```bash
# Update package list
sudo apt update

# Install Java (required by Spark)
sudo apt install -y openjdk-17-jdk

# Set environment variable for Python workers
echo "export PYSPARK_PYTHON=python3" >> ~/.bashrc
source ~/.bashrc

# Install git and Python package manager
sudo apt install -y git python3-pip

# Install PySpark (version must match cluster)
python3 -m pip install pyspark==4.1.1 --user

# Useful Python packages
python3 -m pip install pandas matplotlib --user

# Clone course examples
git clone https://github.com/usamazf/DE1-Spark.git

# Install JupyterLab
python3 -m pip install jupyterlab --user
```

---

## Step 4: Configure Hostnames

### Why this is necessary?

Spark nodes communicate internally using **hostnames**, not raw IP addresses. To ensure that the **driver**, **master**, and **worker nodes** can reliably resolve and reach each other, we explicitly define hostname-to-IP mappings in `/etc/hosts`.

This step ensures that:
- The **driver** can reach executors
- Executors can reach the **master**
- Spark's internal RPC communication works correctly

Since the cluster uses a predictable private IP range, we predefine all possible hostnames.

---

### Command

```bash
sudo /bin/bash -c 'for ((i=1;i<=255;i++)); do echo "192.168.2.${i} de1-spark-host-${i}" >> /etc/hosts; done'
```

This command:

* Iterates over the private subnet `192.168.2.0/24`
* Maps each IP address to a hostname of the form `de1-spark-host-N`
* Appends the mappings to `/etc/hosts`

> [!WARNING]
> - This command appends **255 entries** to `/etc/hosts`.
> - If you already have entries for `de1-spark-host-*`, you should **remove or back up** `/etc/hosts` before running this command to avoid duplicate or conflicting entries.

---

### Verification

Verify hostname resolution by pinging the Spark master hostname.

1. Take the **last octet** of `<MASTERNODE_PRIVATE_IP>`
   * Example: if `<MASTERNODE_PRIVATE_IP>` is `192.168.2.21`, then `NNN = 21`

2. Run:
   ```bash
   ping de1-spark-host-NNN
   ```

You should see successful replies.

---

## Step 5: Launch Jupyter Notebook and Submit Spark Applications

1. Start Jupyter:
   ```bash
   jupyter lab --no-browser --port=8888
   ```
2. Open [http://localhost:8888](http://localhost:8888) in your browser.
3. Navigate to the cloned examples folder.
4. Run [Lecture1_Example2_with_spark.ipynb](https://github.com/usamazf/DE1-Spark/blob/main/DE1-2026/examples/python/Lecture1_Example2_with_spark.ipynb)
5. Configure SparkSession:
   ```python
   from pyspark.sql import SparkSession
   
   spark_session = SparkSession.builder \
       .master("spark://<MASTERNODE_PRIVATE_IP>:7077") \ # Replace with latest Spark master private IP
       .appName("Your_Name_Example") \
       .config("spark.dynamicAllocation.enabled", True) \
       .config("spark.dynamicAllocation.shuffleTracking.enabled", True) \
       .config("spark.shuffle.service.enabled", False) \
       .config("spark.dynamicAllocation.executorIdleTimeout", "30s") \
       .config("spark.executor.cores", 2) \
       .config("spark.driver.port", 9999) \
       .config("spark.blockManager.port", 10005) \
       .getOrCreate()
   ```

6. Check the Spark UI at [http://localhost:4040](http://localhost:4040) (or 4041, 4042, ...)

> Save notebooks frequently in your own repo. Commit often to avoid data loss.

---

## Step 6: General Guidelines for Cluster Usage

1. **Use dynamic allocation** with a 30s idle timeout and limit cores per app (max 4).
2. Include your **name** in application names.
3. **Kill applications** when done.
4. Run **one app at a time**.
5. Respect other students’ work, and don’t modify cluster VMs.
6. Idle applications may be killed automatically.

> These limits ensure fair usage of the shared cluster.

---

## Step 7: Troubleshooting Tips

| Problem                                | Likely Cause             | Solution                                       |
| -------------------------------------- | ------------------------ | ---------------------------------------------- |
| localhost:8080 doesn’t load            | SSH tunnel inactive      | Check `ssh 130.238.x.y` connection on your local machine            |
| Spark job fails with `VersionMismatch` | Local PySpark != cluster | Ensure PySpark version matches cluster (4.1.0) |
| Executors cannot connect               | /etc/hosts misconfigured | Verify `de1-spark-host-XXX` entries on the Driver VM            |
| Notebook cannot import pyspark         | PYSPARK_PYTHON not set   | Run `source ~/.bashrc`                         |

---

## ✅ Summary

* Understand the **driver vs executor split**
* Set up **SSH port forwarding** for secure access
* Install **local PySpark** for the driver process
* Configure **hostnames** for Spark communication
* Launch Jupyter and **submit applications safely**
* Follow **cluster usage rules** and monitor the Spark UI

> With this setup, you should be able to develop Spark applications locally and have them execute on the shared cluster safely and efficiently.

---