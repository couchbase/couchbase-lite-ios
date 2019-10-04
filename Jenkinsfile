pipeline {
    agent none
    environment {
       PRODUCT = 'couchbase-lite-ios'
       timeout(time: 30, unit: 'MINUTES')
   }
    stages {
        stage('Checkout'){
	    agent { label 'mobile-mac-mini'  }
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
	    agent { label 'mobile-mac-mini'  }
            steps {
                sh """ ./${env.PRODUCT}/Scripts/pull_request_build.sh
                """
            }
        }
	stage('Cleanup'){
	    agent { label 'mobile-mac-mini'  }
	    steps {
		sh """
		rm -rf ${env.PRODUCT}
		"""
	    }
	}
    }
}
