import sys
import json
import os

def write_json(new_data, filename='/nfs/monitoring/targets.json'):
        if not os.path.exists(filename):
                with open(filename, "w") as file:
                        file.write("[]")
                        print("File created.")
        else:
                print("File already exists.")
        with open(filename,'r+') as file:
                # First we load existing data into a dict.
                file_data = json.load(file)
                # Join new_data with file_data inside emp_details
                file_data.append(new_data)
                # Sets file's current position at offset.
                file.seek(0)
                # convert back to json.
                json.dump(file_data, file, indent = 4)


if len(sys.argv) < 3:
    print("Please provide correct number of arguments.")
    sys.exit(1)

arg = sys.argv[1]
compute_ip = sys.argv[2]

if arg == "add":
    # python object to be appended
    y = {"labels":{"job":"telegraf"},"targets":["%s:9125"%compute_ip]}
    print(y)
    write_json(y)

elif arg == "remove":
        with open("/nfs/monitoring/targets.json") as file:
                obj = json.load(file)

    # Iterate through the objects in the JSON and remove the obj once we find it.
        for i in range(len(obj)):
                if obj[i]["targets"] == [f"{compute_ip}:9125"]:
                        obj.pop(i)
                        break

    # Output the updated file with pretty JSON
        with open("/nfs/monitoring/targets.json", "w") as file:
                file.write(json.dumps(obj, sort_keys=True, indent=4, separators=(',', ': ')))

else:
    print("Invalid argument provided.")
