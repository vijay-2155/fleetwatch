# TODO: Migrate from 3.9 python to 3.12
# https://www.python.org/downloads/
FROM redislabs/redismod:latest

RUN apt-get update &&\
    apt-get install -y python python3-pip python3-setuptools python3-distutils curl &&\
    apt clean

RUN curl https://bootstrap.pypa.io/pip/3.9/get-pip.py -o get-pip.py &&\
    python3 get-pip.py

RUN echo never > /etc/rc.local

COPY ./ /redis

RUN pip install --upgrade pip

RUN pip install -r /redis/requirements.txt 
