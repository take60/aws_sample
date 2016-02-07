#!/usr/bin/python
# coding: UTF-8

import sys
import random
import string
def gen_rand_str(length, chars=None):
    if chars is None:
        chars = string.letters
    return ''.join([random.choice(chars) for i in range(length)])

if __name__ == "__main__":

    argvs=sys.argv
    argc = len(argvs)
    if (argc != 3):
        print 'argv[0]=this scriptfile'
        print 'argv[1]=number of rows in dummydata'
        print 'argv[2]=output file name'
        quit()

    num=argvs[1]
    data=[]
    f = open(argvs[2], 'w')
    for i in range(int(num)):
        str="%s,%s\n" %(i,gen_rand_str(2))
        f.writelines(str)

    f.close()
