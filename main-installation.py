import segment.analytics as analytics
import os
import logging
import re
import json

# check version
version_file = "_version.py"
verstr = "unknown"
try:
    verstrline = open(version_file, "rt").read()
except EnvironmentError:
    pass # Okay, there is no version file. Supports backwards compatability with old versions of the app
else:
    version_regex = r"^verstr = ['\"]([^'\"]*)['\"]"
    mo = re.search(version_regex, verstrline, re.M)
    if mo:
        verstr = mo.group(1)
    else:
        print "unable to find version in %s" % (version_file,)
        raise RuntimeError("if %s.py exists, it is required to be well-formed" % (version_file,))

logging.info("Running segment-backup-job version:", verstr)
logging.getLogger('segment').setLevel('DEBUG')

def on_error(error, items):
    print("An error occurred:", error)

analytics.write_key = 'jwq6QffjZextbffljhUjL5ODBcrIvsi5'

user={}
data={}

with open('./tmp', 'r') as file:
    for line in file:
        if "org_id:" in line:
            user["org_id"] = line[8:len(line)-1]
        if "user_id:" in line:
            user["user_id"] = line[9:len(line)-1]
        if "alg_id:" in line:
            user["alg_id"] = line[8:len(line)-1]
        if "sub_id:" in line:
            user["sub_id"] = line[8:len(line)-1]
    # analytics.debug = True
    analytics.on_error = on_error
    analytics.track(
      user["user_id"], 
      'New Install', 
      {
        'installation_uuid': user["sub_id"]
      },
      {
        'groupId': user["org_id"],
      }
    )
    analytics.flush()

