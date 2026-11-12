Here is how to launch a [FIPS](https://en.wikipedia.org/wiki/Federal_Information_Processing_Standards) analysis on [Mbed-TLS](https://github.com/Mbed-TLS/mbedtls):


```bash
# get the awp repo
git clone git@github.com:canonical/awp.git
cd awp/
# create a directory named `mbedtls` (or any other name) to analyze a C program using FIPS
./auto-wp.py --c --driver fips --level 4 --harness opencode mbedtls
cd mbedtls
# install lxd if not installed
sudo snap install --channel=6/stable lxd
# install workshop if not installed
sudo snap install --classic workshop
# now launch  the Workshop:
workshop launch
workshop shell
```

Now in the workshop type: (the shell opens in /project)
```bash
git clone https://github.com/Mbed-TLS/mbedtls.git
opencode --dangerously-skip-permissions   # log in with /connection and choose model
```

Now in Opencode type:
```
/time-loop mbedtls 96
```
This should generate the reports in [mbed-tls-fips-compliance](./mbed-tls-fips-compliance/).
