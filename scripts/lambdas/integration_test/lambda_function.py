import boto3
import base64
import json
import time
import os

ec2 = boto3.client('ec2', region_name='us-east-1')
ssm_client = boto3.client('ssm', region_name='us-east-1')


def lambda_handler(event, context):
    image_tag = event['image_tag']
    ecr_registry = event['ecr_registry']
    media_bucket = event['media_bucket']
    github_token = event.get('github_token', '')

    instance_profile_arn = os.environ['INSTANCE_PROFILE_ARN']
    ssm_prefix = os.environ['SSM_PREFIX']
    invocation_id = context.aws_request_id.replace('-', '')[:12]
    param_name = f"{ssm_prefix}/{image_tag}-{invocation_id}"

    try:
        ssm_client.delete_parameter(Name=param_name)
    except ssm_client.exceptions.ParameterNotFound:
        pass

    template_path = os.path.join(os.path.dirname(__file__), 'smoke_compose.yaml')
    with open(template_path) as f:
        template = f.read()

    compose_yaml = template.format(
        ecr_registry=ecr_registry,
        image_tag=image_tag,
        media_bucket=media_bucket,
    )
    compose_b64 = base64.b64encode(compose_yaml.encode()).decode()

    ami_resp = ssm_client.get_parameter(
        Name='/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64'
    )
    ami_id = ami_resp['Parameter']['Value']

    vpc_resp = ec2.describe_vpcs(Filters=[{'Name': 'isDefault', 'Values': ['true']}])
    default_vpc_id = vpc_resp['Vpcs'][0]['VpcId']
    subnet_resp = ec2.describe_subnets(
        Filters=[
            {'Name': 'vpc-id', 'Values': [default_vpc_id]},
            {'Name': 'defaultForAz', 'Values': ['true']},
        ]
    )
    subnets = [s for s in subnet_resp['Subnets'] if s['AvailabilityZone'] != 'us-east-1e']
    subnet_id = subnets[0]['SubnetId']

    sg_resp = ec2.describe_security_groups(
        Filters=[
            {'Name': 'group-name', 'Values': ['default']},
            {'Name': 'vpc-id', 'Values': [default_vpc_id]},
        ]
    )
    default_sg_id = sg_resp['SecurityGroups'][0]['GroupId']

    auth_flag = f'-H "Authorization: token {github_token}"' if github_token else ''

    user_data = f"""#!/bin/bash
set -e
exec > >(tee /var/log/smoke-test.log) 2>&1

dnf install -y docker
systemctl start docker

mkdir -p /root/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-linux-x86_64 \\
  -o /root/.docker/cli-plugins/docker-compose
chmod +x /root/.docker/cli-plugins/docker-compose

aws ecr get-login-password --region us-east-1 | \\
  docker login --username AWS --password-stdin {ecr_registry}

curl -sf {auth_flag} \\
  https://raw.githubusercontent.com/theolecuyer/detailsnap-web/main/db/schema.sql \\
  -o /tmp/schema.sql

echo '{compose_b64}' | base64 -d > /tmp/compose.yaml

cd /tmp
docker compose up -d

RESULT="failure: services did not become healthy after 7.5 minutes"
for i in $(seq 1 30); do
  sleep 15
  if curl -sf http://localhost:8081/healthz >/dev/null 2>&1 && \\
     curl -sf http://localhost:8082/healthz >/dev/null 2>&1 && \\
     curl -sf http://localhost:8083/healthz >/dev/null 2>&1; then
    RESULT="success"
    break
  fi
  echo "Attempt $i/30: not healthy yet"
done

LOGS=""
if [ "$RESULT" != "success" ]; then
  LOGS=$(docker compose logs 2>&1 | tail -200)
fi

SSM_VALUE=$(jq -n --arg result "$RESULT" --arg logs "$LOGS" '{{"result":$result,"logs":$logs}}' | cut -c1-4096)
aws ssm put-parameter --region us-east-1 \\
  --name "{param_name}" \\
  --value "$SSM_VALUE" \\
  --type String \\
  --overwrite

INSTANCE_ID=$(curl -sf http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 terminate-instances --region us-east-1 --instance-ids "$INSTANCE_ID"
"""

    resp = ec2.run_instances(
        ImageId=ami_id,
        InstanceType='t3.small',
        MinCount=1,
        MaxCount=1,
        NetworkInterfaces=[{
            'AssociatePublicIpAddress': True,
            'DeviceIndex': 0,
            'SubnetId': subnet_id,
            'Groups': [default_sg_id],
        }],
        IamInstanceProfile={'Arn': instance_profile_arn},
        UserData=user_data,
        InstanceInitiatedShutdownBehavior='terminate',
        TagSpecifications=[{
            'ResourceType': 'instance',
            'Tags': [
                {'Key': 'Name', 'Value': f'detailsnap-smoke-{image_tag}'},
                {'Key': 'Purpose', 'Value': 'smoke-test'},
            ],
        }],
    )

    instance_id = resp['Instances'][0]['InstanceId']
    print(f"Launched smoke test instance: {instance_id}")

    for attempt in range(28):
        time.sleep(30)
        try:
            param = ssm_client.get_parameter(Name=param_name)
            raw = param['Parameter']['Value']
            ssm_client.delete_parameter(Name=param_name)
            try:
                ec2.terminate_instances(InstanceIds=[instance_id])
            except Exception:
                pass
            try:
                parsed = json.loads(raw)
                result = parsed.get('result', raw)
                logs = parsed.get('logs', '')
            except Exception:
                result = raw
                logs = ''
            if logs:
                print("=== docker compose logs ===")
                print(logs)
            return {'success': result == 'success', 'message': result, 'instance_id': instance_id}
        except ssm_client.exceptions.ParameterNotFound:
            print(f"Waiting for result... attempt {attempt + 1}/28")

    try:
        ec2.terminate_instances(InstanceIds=[instance_id])
    except Exception:
        pass
    return {'success': False, 'message': 'timeout', 'instance_id': instance_id}
