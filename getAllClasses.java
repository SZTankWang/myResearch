import io.github.classgraph.ClassGraph;
import io.github.classgraph.ScanResult;

import java.util.ArrayList;
import java.util.List;
import java.lang.String;
import java.io.File;
import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;

public class getAllClasses{
	public static void main(String[] args){
		//check package name
		// System.out.println("package is: "+args[0]);

		//use classgraph to read all the class names
		List<String> classNames = new ArrayList<>();
		try (ScanResult scanResult = new ClassGraph().acceptPackages("org.apache.commons.lang3")
        .enableClassInfo().scan()) {
    		classNames.addAll(scanResult.getAllClasses().getNames());
		}

		System.out.println(classNames.toString());
		
		//write classes to file
		//classfile at /home/zhenming/research/<pid>/allClasses.txt

        File all_classes = new File("/home/zhenming/research/Lang/allClasses.txt");
        FileWriter fw = null;
        BufferedWriter bw = null;
        if(!all_classes.exists()){
            System.out.println("[ERROR]: selected-test.txt not exists!");
        }
        
        else{
            //create filewriter and bufferwriter
            try{
                fw = new FileWriter(all_classes,true);
                bw = new BufferedWriter(fw);

            }catch(IOException e){}

        }

		for(int i=0;i<classNames.size();i++){
            if(all_classes.exists() && fw != null && bw != null){
                //write test classes
                try{
                    bw.write(classNames.get(i));
                    bw.write("\n");                    
                }catch(IOException e){}

            }
		}
		try{
			bw.close();
		}catch(Exception e){}
		System.out.println("done reading classes");
	}

}