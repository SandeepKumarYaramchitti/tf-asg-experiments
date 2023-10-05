import boto3

ssm = boto3.client('ssm')
s3 = boto3.resource('s3')


def lambda_handler(event, context):
    instance_id = event['detail']['EC2InstanceId']

    # Download the Ansible playbook from S3
    s3.Bucket('cloudysky-codedeploy-bucket').download_file('install_pm2.yml',
                                                           '/tmp/install_pm2.yml')

    # Execute the Ansible playbook via SSM
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunAnsiblePlaybook',
        Parameters={
            'SourceType': ['S3'],
            'SourceInfo': '{"path": "s3://cloudysky-codedeploy-bucket/install_pm2.yml"}',
            'InstallDependencies': ['Yes'],
            'PlaybookFile': 'install_pm2.yml'
        }
    )
    
    return {
        "statusCode": 200,
        "body": "SSM command sent successfully.",
        "ssmResponse": response
    }


    # ... logic to wait for command to finish and send continue lifecycle action ...
