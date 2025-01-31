from fastapi import FastAPI
from ftplib import FTP
import re
from fastapi.responses import FileResponse

app = FastAPI()

FTP_HOST = "ftp.filelu.com"  # Replace with your FTP server
FTP_USER = "freelancer"    # Replace with your FTP username
FTP_PASS = "freelancer"    # Replace with your FTP password

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
    """Lists files & directories from an optional path"""
    try:
        ftp = FTP(FTP_HOST)
        ftp.login(user=FTP_USER, passwd=FTP_PASS)
        ftp.set_pasv(True)
        
        # Navigate to requested path
        ftp.cwd(path) if path else ftp.cwd("/")
        
        files = []
        ftp.retrlines('LIST', files.append)
        
        return {"path": path, "items": parse_ftp_listing(files)}
    except Exception as e:
        return {"error": str(e)}

@app.get("/download/{path:path}")
def download_file(path: str):
    """Downloads a file from FTP"""
    try:
        ftp = FTP(FTP_HOST)
        ftp.login(user=FTP_USER, passwd=FTP_PASS)
        ftp.set_pasv(True)
        
        local_filename = f"/{path.split('/')[-1]}"  # Temporary storage
        with open(local_filename, "wb") as f:
            ftp.retrbinary(f"RETR {path}", f.write)
        
        return FileResponse(local_filename, filename=path.split("/")[-1])
    except Exception as e:
        return {"error": str(e)}
