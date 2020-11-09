# Concrexit nix initial setup

`nix-shell setup.nix`

Set your AWS client credentials:

```sh
export AWS_ACCESS_KEY=...
export AWS_SECRET_KEY=...
```

Now you can start the instance (feel free to copy the whole text):

```sh
# This is the production subnet
export subnet_id=subnet-072547905992bb9a1

# Create instance with the NixOS AMI
instance_info=$(ec2-run-instances ami-02c34db5766cc7013 --region eu-west-1 -k concrexit --subnet $subnet_id --instance-type t2.micro --block-device-mapping '/dev/xvda=:20' --group sg-05b2701b8e277cb69)

# We need the instance ID for the next two commands
instance_id=$(echo "$instance_info" | grep "INSTANCE" | cut -f 2)

# Grep the public key from the instance description
public_ip=$(ec2-describe-instances --region eu-west-1 $instance_id | grep "NICASSOCIATION" | cut -f 2)

# Set the name
ec2-create-tags --region eu-west-1 $instance_id -t Name=concrexit-staging

echo "You can now login with"
echo "ssh -i concrexit.pem root@$public_ip"
```

You need to wait a bit before logging in to allow the SSH server to start up.

Build the machine configuration:

```sh
# Get the Nix hash of the machine config
nix_hash=$(nix-build -A machine)

NIX_SSHOPTS="-i concrexit.pem" nix-copy-closure --to root@$public_ip $nix_hash
ssh -i concrexit.pem root@$public_ip -- $nix_hash/bin/switch-to-configuration switch
```
