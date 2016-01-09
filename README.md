# CodingCloud - encoder/render backend

#Run
perl encoder.pl

#Stop
strg+c  or 'kill -2 pid' to interrupt the running prozess

#setup

- install perl
- enable Network-Connection to Server which store the content (Firewall Port 445 for smb)
- enable Network-Connection to Server which hosting the php-frontend and mysql Database (Port 80,443,3306)

- mount content Share 
- install ffmpeg, ffmbc, blender (if not installed the backend will disable it automatically)
- edit encoder.cfg (edit Mysql-Host, User, Passwd and PATH to mounted SMB-Share)



be shure to install following perl modules.
I recommened to use cpan

- Config::Simple
- Config
- Sys::CpuAffinity
- Net::Address::IP::Local
- Socket
- Sys::Hostname
- DBI
- Parallel::ForkManager
- FindBin
- IPC::Run qw(start pump)
