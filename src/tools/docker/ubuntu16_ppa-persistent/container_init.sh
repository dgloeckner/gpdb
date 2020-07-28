export DATA_DIR="/data"
GREENPLUM_INSTALL_DIR=`find /opt/ -maxdepth 1 -type d -name "greenplum*"`
echo "GREENPLUM_INSTALL_DIR: $GREENPLUM_INSTALL_DIR"
echo "Configured segments: $NUMSEGMENTS"

# This container is only used for testing so we can assume it's running as a privileged container.
echo "Increasing system limits for semaphores. This requires to run the container as privileged!"
# SEMMSL	maximum number of semaphores per array
# SEMMNS	maximum semaphores system-wide
# SEMOPM	maximum operations per semop call
# SEMMNI	maximum arrays
sysctl -w kernel.sem="10000     640000   640      2560"

if [ ! -f "$GREENPLUM_INSTALL_DIR/greenplum_path.sh" ]; then
	echo '========================> Install GPDB'
	apt-get update
	apt install -y \
		software-properties-common \
		less \
		ssh \
		sudo \
		time \
		libzstd1-dev \
    locales \
		python \
    iputils-ping
	add-apt-repository -y ppa:greenplum/db
	apt-get update

	apt install -y greenplum-db
	export GREENPLUM_INSTALL_DIR=`find /opt/ -maxdepth 1 -type d -name "greenplum*"`
	echo "Greenplum was installed here: $GREENPLUM_INSTALL_DIR"
	source "$GREENPLUM_INSTALL_DIR/greenplum_path.sh"
	locale-gen en_US.utf8
fi

if [ ! -d "$DATA_DIR/gpdata" ]; then
	echo '========================> Make $DATA_DIR/gpdata/'
	mkdir -p $DATA_DIR/gpdata/gpdata1
	mkdir -p $DATA_DIR/gpdata/gpdata2
	mkdir -p $DATA_DIR/gpdata/gpmaster
fi
dataDirs="$DATA_DIR/gpdata/gpdata1"
for seg in $(seq 2 $NUMSEGMENTS);
do
  dataDirs="$dataDirs $DATA_DIR/gpdata/gpdata2"
done
echo "Data dirs: $dataDirs"

if [ ! -f "$DATA_DIR/gpdata/gpinitsystem_singlenode" ]; then
	echo '========================> Make gpinitsystem_singlenode and hostlist_singlenode'
	echo 'ARRAY_NAME="GPDB SINGLENODE"' > $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'MACHINE_LIST_FILE='$DATA_DIR'/gpdata/hostlist_singlenode' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'SEG_PREFIX=gpsne' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'PORT_BASE=40000' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo "declare -a DATA_DIRECTORY=($dataDirs)" >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'MASTER_HOSTNAME=dwgpdb' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'MASTER_DIRECTORY='$DATA_DIR'/gpdata/gpmaster' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'MASTER_PORT=5432' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'TRUSTED_SHELL=ssh' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'CHECK_POINT_SEGMENTS=8' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'ENCODING=UNICODE' >> $DATA_DIR/gpdata/gpinitsystem_singlenode
	echo 'DATABASE_NAME=gpadmin' >> $DATA_DIR/gpdata/gpinitsystem_singlenode

	echo $HOSTNAME > $DATA_DIR/gpdata/hostlist_singlenode
fi

if [ ! -d "/home/gpadmin" ]; then
	echo '========================> Add gpadmin'
	useradd -s /bin/bash -md /home/gpadmin/ gpadmin
	chown gpadmin -R $DATA_DIR/gpdata
	echo  "export DATA_DIR=$DATA_DIR" >> /home/gpadmin/.profile
	echo  "export MASTER_DATA_DIRECTORY=$DATA_DIR/gpdata/gpmaster/gpsne-1" >> /home/gpadmin/.profile
	echo  "export GPHOME=$GREENPLUM_INSTALL_DIR" >> /home/gpadmin/.profile
	echo  "source $GPHOME/greenplum_path.sh" >> /home/gpadmin/.profile

	echo  "export DATA_DIR=$DATA_DIR" >> /home/gpadmin/.bashrc
	echo  "export MASTER_DATA_DIRECTORY=$DATA_DIR/gpdata/gpmaster/gpsne-1" >> /home/gpadmin/.bashrc
	echo  "export GPHOME=$GREENPLUM_INSTALL_DIR" >> /home/gpadmin/.bashrc
	echo  "source $GPHOME/greenplum_path.sh" >> /home/gpadmin/.bashrc

	chown gpadmin:gpadmin /home/gpadmin/.profile
	sudo -u gpadmin mkdir /home/gpadmin/.ssh
	ssh-keygen -f /home/gpadmin/.ssh/id_rsa -t rsa -N ""
	chown -R gpadmin:gpadmin /home/gpadmin/.ssh/*
	echo "Increasing ulimits for gpadmin"
	echo "gpadmin 	 soft     nofile         200000" >> /etc/security/limits.conf
	echo "gpadmin    hard     nofile         200000" >> /etc/security/limits.conf
  echo "gpadmin    soft     nproc         200000" >> /etc/security/limits.conf
  echo "gpadmin    hard     nproc         200000" >> /etc/security/limits.conf
fi

echo '========================> GPDB is starting...'
/etc/init.d/ssh start
sleep 2
chown gpadmin:gpadmin /gpdb_start.sh
chmod +x /gpdb_start.sh
su - gpadmin bash -c '/gpdb_start.sh'
echo "Increasing memory limit for segments and master"
su - gpadmin bash -c 'gpconfig -c gp_vmem_protect_limit -v 500000'

echo "Increasing CPUs per segment"
su - gpadmin bash -c 'gpconfig -c gp_resqueue_priority_cpucores_per_segment -v 10'

echo "Increasing cache limit per worker (make it 10000 MB; to be tested)"
su - gpadmin bash -c 'gpconfig -c gp_vmem_protect_segworker_cache_limit -v 10000'

echo "Restarting cluster"
su - gpadmin bash -c 'gpstop -a; gpstart -a'
