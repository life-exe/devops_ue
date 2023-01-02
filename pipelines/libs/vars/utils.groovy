def SlackColorFromBuildResult(result){
    if("${result}" == 'SUCCESS') return '#18A558'
    if("${result}" == 'ABORTED') return '#6e6e6e'
    if("${result}" == 'UNSTABLE') return '#fcba03'
    return '#FF0000'
}

// https://stackoverflow.com/a/54176916
def loadEnvironmentVariables(path){
    def props = readProperties  file: path
    keys= props.keySet()
    for(key in keys) {
        value = props["${key}"]
        env."${key}" = "${value}"
    }
} 