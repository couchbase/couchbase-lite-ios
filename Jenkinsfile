pipeline {
    agent { label 'ios-pull-request' }
    environment {
       PRODUCT = 'couchbase-lite-ios'
   }
    stages {
        stage('Checkout'){
            steps {
                sh """
                    git clone https://github.com/couchbase/${env.PRODUCT}.git
                    pushd ${env.PRODUCT}
                    git submodule update --init --recursive
                    popd
                """
            }
        }
        stage('Build'){
            steps {
                sh """ ./${env.PRODUCT}/Scripts/pull_request_build.sh
                """
            }
        }
    }
}
