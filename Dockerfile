FROM ubuntu:16.04

MAINTAINER Mohamed Nadjib Mami <mami@cs.uni-bonn.de>

# Install necessary utility software
RUN set -x && \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends curl vim openjdk-8-jdk-headless apt-transport-https openssh-server openssh-client wget maven git python telnet wget unzip time && \
    # cleanup
    apt-get clean

# Update environment
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64/
ENV HADOOP_VERSION 2.9.2
ENV HADOOP_URL https://archive.apache.org/dist/hadoop/core/hadoop-2.9.2/hadoop-2.9.2.tar.gz

# Configure SSH
# COPY ssh_config /root/.ssh/config
RUN ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa \
    && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys \
    && chmod 0600 ~/.ssh/authorized_keys

# Install Hadoop
ENV HADOOP_HOME /usr/local/hadoop
ENV HADOOP_CONF_DIR $HADOOP_HOME/etc/hadoop
ENV HDFS_PORT 9000

RUN set -x && \
    curl -fSL -o - "$HADOOP_URL" | tar xz -C /usr/local && \
    mv /usr/local/hadoop-2.9.2 /usr/local/hadoop

# Configure Hadoop
RUN sed -i 's@\${JAVA_HOME}@'"$JAVA_HOME"'@g' $HADOOP_CONF_DIR/hadoop-env.sh
RUN sed -ri ':a;N;$!ba;s@(<configuration>).*(</configuration>)@\1<property><name>fs.default.name</name><value>hdfs://localhost:'"$HDFS_PORT"'</value></property>\2@g' $HADOOP_CONF_DIR/core-site.xml
RUN sed -ri ':a;N;$!ba;s@(<configuration>).*(</configuration>)@\1<property><name>dfs.replication</name><value>1</value></property>\2@g' $HADOOP_CONF_DIR/hdfs-site.xml

# Install Hive
ENV HIVE_VERSION 3.1.1
ENV HIVE_URL https://archive.apache.org/dist/hive/hive-3.1.1/apache-hive-3.1.1-bin.tar.gz
ENV HIVE_HOME /usr/local/hive

RUN set -x && \
    curl -fSL -o - "$HIVE_URL" | tar xz -C /usr/local && \
    mv /usr/local/apache-hive-$HIVE_VERSION-bin /usr/local/hive

RUN wget https://repo.maven.apache.org/maven2/mysql/mysql-connector-java/8.0.13/mysql-connector-java-8.0.13.jar && \
    mv mysql-connector-java-8.0.13.jar /usr/local/hive/lib

COPY evaluation/Hive_files/hive-site.xml $HIVE_HOME/conf/

# Install Presto (Server and CLI)
ENV PRESTO_VERSION 304
ENV PRESTO_URL     https://repo.maven.apache.org/maven2/io/prestosql/presto-server/304/presto-server-304.tar.gz
ENV PRESTO_CLI_URL https://repo.maven.apache.org/maven2/io/prestosql/presto-cli/304/presto-cli-304-executable.jar

RUN set -x && \
    curl -fSL -o - "$PRESTO_URL" | tar xz -C /usr/local && \
    mv /usr/local/presto-server-${PRESTO_VERSION} /usr/local/presto

RUN set -x && \
    wget ${PRESTO_CLI_URL} && \
    mv presto-cli-${PRESTO_VERSION}-executable.jar /usr/local/presto/presto && \
    chmod +x /usr/local/presto/presto

# Configure Presto
ENV PRESTO_HOME /usr/local/presto

RUN set -x && \
    mkdir ${PRESTO_HOME}/etc && \
    mkdir ${PRESTO_HOME}/etc/catalog && \
    mkdir /var/lib/presto
    # If you change the latter, also change it in node.properties config file

COPY evaluation/Presto_files/config/* /usr/local/presto/etc/
COPY evaluation/Presto_files/catalog/* /usr/local/presto/etc/catalog/

# Install MongoDB
RUN set -x && \
    wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add - && \
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list && \
    apt-get update && \
    apt-get install -y mongodb-org && \
    mkdir -p /data/db

# Install Cassandra
RUN wget https://archive.apache.org/dist/cassandra/debian/pool/main/c/cassandra/cassandra_3.11.13_all.deb -o - && \ 
    dpkg -i cassandra_3.11.13_all.deb && \ 
    apt-get update

# Install MySQL
RUN set -x && \
    echo 'mysql-server mysql-server/root_password password root' | debconf-set-selections  && \
    echo 'mysql-server mysql-server/root_password_again password root' | debconf-set-selections && \
    apt-get update && \
    apt-get install -y --no-install-recommends vim && \
    apt-get -y install mysql-server
    # to solve "Can't open and lock privilege tables: Table storage engine for 'user' doesn't have this option"
    # sed -i -e "s/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/my.cnf && \
    # /etc/init.d/mysql start

# Install Spark
ENV SPARK_VERSION 2.4.0
RUN set -x  && \
    curl -fSL -o - https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop2.7.tgz | tar xz -C /usr/local && \
    mv /usr/local/spark-${SPARK_VERSION}-bin-hadoop2.7 /usr/local/spark

# Generate BSBM data
RUN set -x && \
    apt-get update --fix-missing && \
    apt-get install -y unzip

RUN set -x && \
    wget -O bsbm.zip https://sourceforge.net/projects/bsbmtools/files/latest/download && \
    unzip bsbm.zip && \
    rm bsbm.zip && \
    cd bsbmtools-0.2 && \
    ./generate -fc -pc 1000 -s sql -fn /root/data/input && \
    cd /root/data/input && \
    ls && \
    rm 01* 02* 05* 06* 07*

# Due to a (yet) explaineable behavior from spark-submit assembly plugin,
# jena-arq and presto-jdbc are not being picked up during the assembly of Squerall
# So we will provide them temporarily during spark submit
ENV JENA_VERSION 3.9.0

RUN set -x && \
    wget https://repo.maven.apache.org/maven2/org/apache/jena/jena-arq/3.9.0/jena-arq-3.9.0.jar && \
    mv jena-arq-3.9.0.jar /root

RUN set -x && \
    wget https://repo.maven.apache.org/maven2/io/prestosql/presto-jdbc/304/presto-jdbc-304.jar && \
    mv presto-jdbc-304.jar /root

COPY evaluation/SQLtoNOSQL /root/SQLtoNOSQL
COPY evaluation/input_files/* /root/input/
COPY evaluation/input_files/queries/* /root/input/queries/

# just to force rebuild
RUN ls

RUN set -x && \
    # Install Squerall
    cd /usr/local && \
    git clone https://github.com/EIS-Bonn/Squerall.git && \
    cd Squerall && \
    mvn package

COPY evaluation/scripts/* /root/

RUN echo "\nbash /root/welcome.sh\n" >> /root/.profile

CMD ["/bin/bash","--login"]
