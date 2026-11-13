Here is how to launch a [Risk Management Framework](https://csrc.nist.gov/projects/risk-management/about-rmf) analysis on [sudo-rs](https://github.com/trifectatechfoundation/sudo-rs):

```bash
# get the awp repo
git clone git@github.com:canonical/awp.git
cd awp/
# create a directory named `sudo-rs-analyze` (or any other name) to analyze a rust program
./auto-wp.py --rust sudo-rs-analyze
cd sudo-rs-analyze
# we need `libpam0g` for sudo-rs:
sed -i 's/^apt-get install tmux curl$/& libpam0g-dev/' .workshop/autowp-packages/hooks/setup-base
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
git clone --branch v0.2.15 --depth 1 https://github.com/trifectatechfoundation/sudo-rs.git sudo-rs
claude --dangerously-skip-permissions   # log in with /login the first time
```

Now in Claude type
```
/time-loop sudo-rs 96
```

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
Using that I found [this issue](f20-report.md) actually reported 1 hours earlier than me by [Squell](https://github.com/trifectatechfoundation/sudo-rs/issues/1728).

