#/bin/bash

bucketname=$1
aws s3 mb s3://${bucketname} --region ap-northeast-1
python make_dummydata.py 1000000 dummy1.csv
python make_dummydata.py 1000000 dummy2.csv

aws s3 mv dummy1.csv s3://${bucketname}/emrtest/dummy1.csv
aws s3 mv dummy2.csv s3://${bucketname}/emrtest/dummy2.csv

