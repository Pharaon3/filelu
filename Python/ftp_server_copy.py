from fastapi import FastAPI
from ftplib import FTP_TLS
import re
from fastapi.responses import FileResponse

app = FastAPI()

FTP_HOST = "ftp.filelu.com"  # Replace with your FTPS server
FTP_PORT = 990                # Explicitly use port 990
FTP_USER = "freelancer"    
FTP_PASS = "freelancer"    

def connect_ftps():
    """Establish FTPS connection"""
    ftps = FTP_TLS()
    ftps.connect(FTP_HOST, FTP_PORT)  # Connect using port 990
    ftps.login(FTP_USER, FTP_PASS)
    ftps.prot_p()  # Set secure data connection (Required for FTPS)
    return ftps

def parse_ftp_listing(ftp_listing):
    """Parses FTP LIST output to separate files and directories"""
    items = []
    for line in ftp_listing:
        parts = re.split(r"\s+", line, maxsplit=8)
        if len(parts) < 9:
            continue
        name = parts[8]
        is_dir = line.startswith('d')  # FTP directories start with 'd'
        items.append({"name": name, "is_dir": is_dir})
    return items

@app.get("/list-files")
@app.get("/list-files/{path:path}")
def list_ftp_files(path: str = ""):
    """Lists files & directories from FTPS server"""
    try:
        ftps = connect_ftps()
        ftps.cwd(path) if path else ftps.cwd("/")
        
        files = []
        ftps.retrlines('LIST', files.append)
        ftps.quit()
        
        return {"path": path, "items": parse_ftp_listing(files)}
    except Exception as e:
        return {"error": str(e)}

@app.get("/download/{path:path}")
def download_file(path: str):
    """Downloads a file from FTPS"""
    try:
        ftps = connect_ftps()
        
        local_filename = f"/tmp/{path.split('/')[-1]}"  # Temporary storage
        with open(local_filename, "wb") as f:
            ftps.retrbinary(f"RETR {path}", f.write)
        
        ftps.quit()
        return FileResponse(local_filename, filename=path.split("/")[-1])
    except Exception as e:
        return {"error": str(e)}
