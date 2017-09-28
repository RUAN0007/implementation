# OrpheusDB: Bolt-On Versioning for Relational Databases
## Prerequisite 
* Install PostgresSQL(PG) for OrpheusDB backend
⋅⋅* Either through apt-get via sudo
⋅⋅* Or build on slave-40 on ciidaa
* Create a PG super user and PG db (NOTE: the pwd of the PG must be 'password')
* Configure Orpheus home directory, PG's host and port at config.yaml
* Install OrpheusDB by cmd `cd <Orpheus_Home>; pip install .`
* Configure the created PG's user, pwd and db via cmd `orpheus config`


## Usage
* Start up PG server via cmd `postgres -D <path to data directory>
* Run benchmark script `./benchmark.sh <Path_to_Data_File_from_Table_Gen> <Path_to_Query_File_from_Table_Gen>`
NOTE: Data file and query file must be placed under test/ directory. 

The console output will stick to the following format.

\<line-num\>: \<description\>  
1: \<Initial Loading Latency in ms\>, e.g, 100  
2: \<Storage Consumption in MB\>, 10  
3: \<Aggregation Latency in ms\>, 50  
// The commit latency in ms for next <# of version> line, e.g, with 3 versions:  
4: 121  
5: 122  
6: 126  
// The storage increment in MB for next <# of version> e.g, with 3 versions:  
7: 3  
8: 4  
9: 5  
// The diff latency in ms for next <# of version> + 1, e.g, with 3 versions,   
10: 0.1 // Diff with base itself  
11: 1 // Diff v1 with base  
12: 2 // Diff v2 with base  
13: 3 // Diff v3 with base 

User can switch to verbose output via cmd `VERBOSE=true ./benchmark.sh ...`

