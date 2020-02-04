#!/bin/bash

##############################################################
#                                                            #
# This sample demonstrates the following concepts:           #
#                                                            #
# * Cognito User Pool creation                               #
# * Cognito User Pool Client creation                        #
# * Cognito Identity Pool creation                           #
# * IAM role creation                                        #
# * S3 bucket creation                                       #
# * S3 bucket policies per cognito user                      #
# * Cleans up all the resources created                      #
#                                                            #
##############################################################

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variable declarations
PROJECT_DIR=$PWD
AWS_PROFILE=<!-- ADD_YOUR_AWS_CLI_PROFILE_HERE -->
AWS_REGION=$(aws configure get region --output text --profile ${AWS_PROFILE})
IAM_CAPABILITIES=CAPABILITY_NAMED_IAM
STACK_NAME=cognito-with-s3
CFN_STACK_TEMPLATE=stack-template.yml
USER_POOL_NAME=cognito-with-s3-user-pool
IDENTITY_POOL_NAME=cognito-with-s3-identity-pool
USER_ROLE_NAME=cognito-with-s3-role
USER_POLICY_NAME=cognito-with-s3-policy
ALLOWED_ORIGINS='"*"'
WEBPACK_CONFIG_FILE=webpack/dev.js
UNDEPLOY_FILE=aws-undeploy.sh

###########################################################
#                                                         #
#  Validate the CloudFormation templates                  #
#                                                         #
###########################################################

echo -e "[${LIGHT_BLUE}INFO${NC}] Validating CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC}.";
cat ${CFN_STACK_TEMPLATE} | xargs -0 aws cloudformation validate-template --profile ${AWS_PROFILE} --template-body

# assign the exit code to a variable
CFN_STACK_TEMPLATE_VALIDAION_CODE="$?"

# check the exit code, 255 means the CloudFormation template was not valid
if [ $CFN_STACK_TEMPLATE_VALIDAION_CODE != "0" ]; then
    echo -e "[${RED}FATAL${NC}] CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC} failed validation with non zero exit code ${YELLOW}$CFN_STACK_TEMPLATE_VALIDAION_CODE${NC}. Exiting.";
    exit 999;
fi

echo -e "[${GREEN}SUCCESS${NC}] CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC} is valid.";

###########################################################
#                                                         #
#  Execute the CloudFormation templates                   #
#                                                         #
###########################################################

echo -e "[${LIGHT_BLUE}INFO${NC}] Exectuing the CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC}.";
aws cloudformation create-stack \
	--template-body file://${CFN_STACK_TEMPLATE} \
	--stack-name ${STACK_NAME} \
	--capabilities ${IAM_CAPABILITIES} \
	--parameters \
	ParameterKey=UserPoolName,ParameterValue=${USER_POOL_NAME} \
	ParameterKey=IdentityPoolName,ParameterValue=${IDENTITY_POOL_NAME} \
	ParameterKey=UserRoleName,ParameterValue=${USER_ROLE_NAME} \
	ParameterKey=UserPolicyName,ParameterValue=${USER_POLICY_NAME} \
	ParameterKey=AllowedOrigins,ParameterValue=${ALLOWED_ORIGINS} \
	--profile ${AWS_PROFILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] Waiting for the CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC} to complete.";
aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME} --profile ${AWS_PROFILE}

###########################################################
#                                                         #
#  Create the webpack config                              #
#                                                         #
###########################################################

# get the stack outputs
USER_POOL_ID=$(
aws cloudformation describe-stacks \
	--stack-name ${STACK_NAME} \
	--profile ${AWS_PROFILE} \
	--output text \
	--query "Stacks[0].Outputs[?OutputKey == 'UserPoolId'][OutputValue]"
);

USER_POOL_CLIENT_ID=$(
aws cloudformation describe-stacks \
	--stack-name ${STACK_NAME} \
	--profile ${AWS_PROFILE} \
	--output text \
	--query "Stacks[0].Outputs[?OutputKey == 'UserPoolClientId'][OutputValue]"
);

IDENTITY_POOL_ID=$(
aws cloudformation describe-stacks \
	--stack-name ${STACK_NAME} \
	--profile ${AWS_PROFILE} \
	--output text \
	--query "Stacks[0].Outputs[?OutputKey == 'IdentityPoolId'][OutputValue]"
);

FILE_BUCKET_NAME=$(
aws cloudformation describe-stacks \
	--stack-name ${STACK_NAME} \
	--profile ${AWS_PROFILE} \
	--output text \
	--query "Stacks[0].Outputs[?OutputKey == 'FileBucketName'][OutputValue]"
);

echo -e "[${LIGHT_BLUE}INFO${NC}] Creating the webpack config file with the following values.";
echo -e "* ${YELLOW}$USER_POOL_ID${NC}";
echo -e "* ${YELLOW}$USER_POOL_CLIENT_ID${NC}";
echo -e "* ${YELLOW}$IDENTITY_POOL_ID${NC}";
echo -e "* ${YELLOW}$FILE_BUCKET_NAME${NC}";

# delete any previous instance of ${WEBPACK_CONFIG_FILE}
if [ -f "${WEBPACK_CONFIG_FILE}" ]; then
    rm "${WEBPACK_CONFIG_FILE}"

fi

# create the ${WEBPACK_CONFIG_FILE} file
cat > "${WEBPACK_CONFIG_FILE}" <<EOF
module.exports = {
  'AWS_REGION': '${AWS_REGION}',
  'USER_POOL_ID': '${USER_POOL_ID}',
  'USER_POOL_CLIENT_ID': '${USER_POOL_CLIENT_ID}',
  'IDENTITY_POOL_ID': '${IDENTITY_POOL_ID}',
  'FILE_BUCKET_NAME': '${FILE_BUCKET_NAME}'
}
EOF

###########################################################
#                                                         #
#  Build the webpack app for testing                      #
#                                                         #
###########################################################

echo -e "[${LIGHT_BLUE}INFO${NC}] Export the ${YELLOW}WEBPACK_CONFIG${NC} variable.";
export WEBPACK_CONFIG=./${WEBPACK_CONFIG_FILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] Building the webpack application.";
npm run build:dev

echo -e "[${LIGHT_BLUE}INFO${NC}] Webpack applicatiion can be accessed at ${GREEN}${PWD}/dist/index.html${NC}.";

###########################################################
#                                                         #
# Undeployment file creation                              #
#                                                         #
###########################################################

# delete any previous instance of undeploy.sh
if [ -f "$UNDEPLOY_FILE" ]; then
    rm $UNDEPLOY_FILE
fi

cat > $UNDEPLOY_FILE <<EOF
#!/bin/bash

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

echo -e "[${LIGHT_BLUE}INFO${NC}] Delete S3 Bucket ${YELLOW}${FILE_BUCKET_NAME}${NC}.";
aws s3 rm s3://${FILE_BUCKET_NAME}/ --recursive --profile ${AWS_PROFILE}
aws s3 rb s3://${FILE_BUCKET_NAME} --profile ${AWS_PROFILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] Terminating cloudformation stack ${YELLOW}${STACK_NAME}${NC} ....";
aws cloudformation delete-stack --stack-name ${STACK_NAME} --profile ${AWS_PROFILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] Waiting for the deletion of cloudformation stack ${YELLOW}${STACK_NAME}${NC} ....";
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --profile ${AWS_PROFILE}

aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --profile ${AWS_PROFILE}
EOF

chmod +x $UNDEPLOY_FILE