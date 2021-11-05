import sys
import xml.etree.ElementTree as ET



work_dir = sys.argv[1]

print("searching in dir {dir}".format(dir=work_dir))

tree = ET.parse(work_dir+'/pom.xml')

root = tree.getroot()
print(root.tag)

ns = "{http://maven.apache.org/POM/4.0.0}";
ET.register_namespace("","http://maven.apache.org/POM/4.0.0")

new_v = 1.8 #desired version
	
for child in root.findall(ns+"properties"):
	source = child.find(ns+"maven.compile.source")
	target = child.find(ns+"maven.compile.target")
	print(source,target)
	# change the version to new_v
	source.text = str(new_v)
	target.text = str(new_v)

tree.write(work_dir+"/pom.xml")

	