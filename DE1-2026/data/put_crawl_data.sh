#!/bin/bash

output_files_path=/home/ubuntu/DE1-Spark/DE-2025/data/crawl
main_link_address=https://data.commoncrawl.org/crawl-data/CC-MAIN-2023-40/wet.paths.gz
max_page_to_crawl=20

# Make a temporary folder to store intermediate results
mkdir __temp__ && cd __temp__
wget -nv $main_link_address
gzip -d wet.paths.gz

mkdir -p $output_files_path

# Process top
while IFS= read -r line; do
    # https://data.commoncrawl.org/crawl-data/CC-MAIN-2023-23/segments/1685224657735.85/wet/CC-MAIN-20230610164417-20230610194417-00799.warc.wet.gz
    # echo "Downloading https://data.commoncrawl.org/$line"
    wget -nv "https://data.commoncrawl.org/$line"

    # Extract the currently downloaded WET file
    gz_file=$(echo $line | cut -d "/" -f 6)
    gzip -d $gz_file

    # Push the current crawl file to HDFS
    /home/ubuntu/hadoop/bin/hdfs dfs -put ${gz_file%.gz} /data/crawl/

    # Move the extracted file to crawl folder
    mv  ${gz_file%.gz} $output_files_path/${gz_file%.gz}

    max_page_to_crawl=$((max_page_to_crawl - 1))
    if [ $max_page_to_crawl -eq 0 ]; then
        break
    fi
done < wet.paths

cd .. && rm -rf __temp__