pipeline {
    agent none
    environment {
       PRODUCT = 'couchbase-lite-ios'
   }
    stages {
        stage('Checkout'){
            agent { label 'master' }
            steps {
                cleanWs()
                sh """
                    git clone https://github.com/couchbase/${env.PRODUCT}.git
                    pushd ${env.PRODUCT}
                    git submodule update --init --recursive
                    popd
                """
            }
        }
        stage('Build'){
            agent { label 'master' }
            steps {
                sh ''' couchbase-lite-ios/Scripts/pull_request_build.sh
                '''
            }
        }
    }
}
