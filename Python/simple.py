from ftplib import FTP

# Connect to the FTP server
ftp = FTP('ftp.filelu.com')
ftp.login(user='freelancer', passwd='freelancer')

# Enable passive mode
ftp.set_pasv(True)

# List files
ftp.retrlines('LIST')

# Quit the session