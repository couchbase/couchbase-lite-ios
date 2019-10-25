pipeline {
    agent { label 'mobile-builder-ios-pull-request'  }
    environment {
       PRODUCT = 'couchbase-lite-ios-ee'
       BRANCH = "${BRANCH_NAME}"
   }
    stages {
        stage('Checkout'){
            steps {
                sh """
                    git clone https://github.com/couchbaselabs/${env.PRODUCT}.git
                    pushd ${env.PRODUCT}
                    git submodule update --init --recursive
                    ./Scripts/prepare_project.sh
                    cd couchbase-lite-ios
		    git checkout ${BRANCH}
		    git pull origin ${BRANCH}
                    popd
                """
            }
        }
        stage('Build'){
            steps {
                sh """ ./${env.PRODUCT}/couchbase-lite-ios/Scripts/pull_request_build.sh
                """
            }
        }
    }
}
