# This is a basic wrapper for PHOENIX for use for example in Jupyter Notebooks

import subprocess
import xmltodict
import pathlib
import sys
from IPython.display import clear_output
import platform
import glob
import urllib
import os
import stat

class pyphoenix:
    bin_path=None
    have_bin=None
    use_gpu=None
    precision=None
    debug=None
    sfml=None
    has_gpu=None
    gpu_id=None
    
    
    def __init__(self,precision="fp32",use_gpu=True,gpu_id=0,sfml=False,hint_path=None,result_path=None,debug=False):
        self.precision=precision
        self.use_gpu=use_gpu
        if platform.system()=="Darwin":
            self.use_gpu=False
            print("Warning: GPU computation is not yet supported in PHOENIX for MacOS.")
        self.debug=debug
        self.sfml=sfml
        self.has_gpu=self.check_gpu()
        self.gpu_id=gpu_id
        self.have_bin=False
        if use_gpu and not self.has_gpu:
            print("Warning: GPU requested but GPU not detected, falling back to CPU simulation.")
        if result_path is None:
            self.result_path=os.path.abspath("tmp_phoenix_results")
        else:
            self.result_path=os.path.abspath(result_path)
        if hint_path is None:
            #try environment variable
            if "PHOENIX_PATH" in os.environ:
                path=os.path.abspath(os.environ["PHOENIX_PATH"])
                self.find_binary(path)
            else:
                self.find_binary(os.path.abspath("../.."))                
        else:
            self.find_binary(os.path.abspath(hint_path))

       

    def check_gpu(self):
        try:
            c=subprocess.check_output(['nvidia-smi',"-x","-q"])
            data_dict = xmltodict.parse(c)
            #if self.debug:
            #    print(data_dict)
            if int(data_dict["nvidia_smi_log"]["attached_gpus"])>0:
                return True
        except:
            return False

    def get_result_path(self):
        return self.result_path

    def find_binary(self,hint_path):
        #search for suitbale binary
        binname=os.path.join(os.path.join(os.path.abspath(hint_path),"**"),"PHOENIX")
        if self.use_gpu:
            binname=binname+"_gpu"
        else:
            binname=binname+"_cpu"
        if self.precision=="fp32":
            binname=binname+"_fp32"
        else:
            binname=binname+"_fp64"
        if self.sfml:
            binname=binname+"_sfml"
        else:
            binname=binname+"*"
        if self.debug:
            print("searching for ",binname)
        binname2=binname
        if platform.system()=="Windows":
            binname2=binname2+".exe"
        re=glob.glob(binname2, recursive = True)
        found=False
        for e in re:
            runstring=e+" --help"
            if self.debug:
                print("trying to run",runstring)
            env = os.environ.copy()
            if not "LD_LIBRARY_PATH" in env:
                env["LD_LIBRARY_PATH"]=""
            env["LD_LIBRARY_PATH"]=env["LD_LIBRARY_PATH"]+":"+os.path.dirname(e)
            try:
                process = subprocess.Popen(runstring.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,env=env, universal_newlines = True)
                self.stdout, self.stderr = process.communicate()
                if process.returncode==0:
                    found=True
                    if self.debug:
                        print("Binary found at",e)
                    self.bin_path=e
                    self.have_bin=True
            except:
                pass
        if not found:
            plat=platform.system()
            print("Warning: no working binary of PHOENIX found, trying to download suitable binary from last release from Github for",plat,platform.machine(),". This probably won't work because your system might be missing dependencies to run this binary.")
            baseurl="https://github.com/robertschade/PHOENIX/releases/download/"
            #baseurl="https://github.com/Schumacher-Group-UPB/PHOENIX/releases/download/"
            tag="latest"
            binname2=os.path.basename(binname).replace("*","")+"_"+plat+"_"+platform.machine()
            if platform.system()=="Windows":
                binname2=binname2+".exe"
            url=baseurl+"/"+tag+"/"+binname2
            if self.debug:
                print("Trying to download",url)
            downloaded=False
            os.makedirs(self.result_path, exist_ok=True)
            binpath=os.path.join(self.result_path, binname2)
                
            try:
                ret=urllib.request.urlretrieve(url,binpath)
                downloaded=True
            except:
                print("Error downloading",url,"to",binpath)
                print("Please consult https://github.com/Schumacher-Group-UPB/PHOENIX. You can open an issue at https://github.com/Schumacher-Group-UPB/PHOENIX/issues/new.")
            if downloaded:
                f = pathlib.Path(binpath)
                f.chmod(f.stat().st_mode | stat.S_IEXEC)
                cmd=binpath+" --help"
                print("Trying to run the downloaded binary (",cmd,")")
                try:    
                    #env = os.environ.copy()
                    #if not "LD_LIBRARY_PATH" in env:
                    #    env["LD_LIBRARY_PATH"]=""
                    #env["LD_LIBRARY_PATH"]=env["LD_LIBRARY_PATH"]+":"+os.path.dirname(binpath)
                    process = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines = True)
                    self.stdout, self.stderr = process.communicate()
                    if process.returncode==0:
                        if self.debug:
                            print("Binary found at",binpath)
                        self.bin_path=binpath
                        self.have_bin=True
                except:
                    print("Downloaded binary is not working on your computer. Please consult https://github.com/Schumacher-Group-UPB/PHOENIX. You can open an issue at https://github.com/Schumacher-Group-UPB/PHOENIX/issues/new.")
            
                
    def run(self,config):
        if not self.have_bin:
            print("PHOENIX binary is missing. Please consult https://github.com/Schumacher-Group-UPB/PHOENIX. You can open an issue at https://github.com/Schumacher-Group-UPB/PHOENIX/issues/new.")
            return
        # Create Target Directories
        os.makedirs(self.result_path, exist_ok=True)
        #convert config deict to string
        runstring=self.bin_path
        for k in config:
            runstring=runstring+" --"+str(k)
            if isinstance(config[k],list):
                for e in config[k]:
                    runstring=runstring+" "+str(e)
            else:
                runstring=runstring+" "+str(config[k])
        #path
        runstring=runstring+" --path "+self.result_path
        #loadFrom
        runstring=runstring+" --path ."
        #sfml
        if not self.sfml:
            runstring=runstring+" -nosfml"
        
        if self.debug:
            print(runstring)

        # Path to the PHOENIX executable. This example requires the fp64 version of PHOENIX
        env = os.environ.copy()
        if not "LD_LIBRARY_PATH" in env:
            env["LD_LIBRARY_PATH"]=""
        env["LD_LIBRARY_PATH"]=env["LD_LIBRARY_PATH"]+":"+os.path.dirname(self.bin_path)
        env["CUDA_VISIBLE_DEVICES"]=str(self.gpu_id)
        
        process = subprocess.Popen(runstring.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,env=env, universal_newlines = True)
        out_block=[]
        for line in process.stdout:
            if self.debug:
                print(line)
            else:
                if line.find("T =")>=0 or line.find("Progress:")>=0 or line.find("Current System:")>=0 or line.find("Runtime:")>=0 or line.find("Time per ps:")>=0:
                    out_block.append(line)
                if line.find("Time per ps:")>=0:
                    clear_output(wait=True)
                    for l in out_block:
                        sys.stdout.write(l)
                    out_block=[]
        self.stdout, self.stderr = process.communicate()
        if process.returncode!=0:
            print("Something went wrong. Please consult https://github.com/Schumacher-Group-UPB/PHOENIX. You can open an issue at https://github.com/Schumacher-Group-UPB/PHOENIX/issues/new.")
            print("Please check the error output:")
            print(self.stderr)
    
    
