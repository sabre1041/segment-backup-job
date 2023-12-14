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
data["rekor_qps_by_api"] = []
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
        if "fulcio_new_certs:" in line:
            data["fulcio_new_certs"] = line[19:len(line)-2]
        if "rekor_new_entries:" in line:
            data["rekor_new_entries"] = line[20:len(line)-2]
        if "rekor_qps_by_api:" in line:
            data["rekor_qps_by_api_string"] = line[17:len(line)-2]
            if data["rekor_qps_by_api_string"] != "":
                rekor_qps_by_api_string = data["rekor_qps_by_api_string"].split("| ")
                for api in rekor_qps_by_api_string:
                    api_attributes = api.split(",")
                    api_attributes_obj= {
                        'method': api_attributes[0][9:len(api_attributes[0])],
                        'status_code': api_attributes[1][12:len(api_attributes[1])],
                        'path': api_attributes[2][5:len(api_attributes[2])],
                        'value': api_attributes[3][6:len(api_attributes[3])],
                    }
                    data["rekor_qps_by_api"].append(api_attributes_obj)
    # analytics.debug = True
    analytics.on_error = on_error       
    analytics.track(
        user["user_id"], 
        'Nightly Usage Metrics', 
        {
            'installation_uuid': user["sub_id"],
            'fulcio_new_certs': data["fulcio_new_certs"],
            'rekor_new_entries': data["rekor_new_entries"],
            'rekor_qps_by_api': data["rekor_qps_by_api"],
        },
        {
            'groupId': user["org_id"],
        }
    )
    analytics.flush()

