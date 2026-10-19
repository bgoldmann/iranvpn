#include <android/log.h>
#include <jni.h>
#include <pthread.h>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <vector>

#include "tun2socks/tun2socks.h"

namespace {
int pipe_stdout[2];
int pipe_stderr[2];
pthread_t thread_stdout;
pthread_t thread_stderr;
const char* ADBTAG = "tun2socks";

void* thread_stderr_func(void*) {
    ssize_t redirect_size;
    char buf[2048];
    while ((redirect_size = read(pipe_stderr[0], buf, sizeof(buf) - 1)) > 0) {
        if (buf[redirect_size - 1] == '\n') --redirect_size;
        buf[redirect_size] = 0;
        __android_log_write(ANDROID_LOG_ERROR, ADBTAG, buf);
    }
    return nullptr;
}

void* thread_stdout_func(void*) {
    ssize_t redirect_size;
    char buf[2048];
    while ((redirect_size = read(pipe_stdout[0], buf, sizeof(buf) - 1)) > 0) {
        if (buf[redirect_size - 1] == '\n') --redirect_size;
        buf[redirect_size] = 0;
        __android_log_write(ANDROID_LOG_INFO, ADBTAG, buf);
    }
    return nullptr;
}

int start_redirecting_stdout_stderr() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    pipe(pipe_stdout);
    dup2(pipe_stdout[1], STDOUT_FILENO);
    setvbuf(stderr, nullptr, _IONBF, 0);
    pipe(pipe_stderr);
    dup2(pipe_stderr[1], STDERR_FILENO);
    if (pthread_create(&thread_stdout, nullptr, thread_stdout_func, nullptr) == -1) return -1;
    pthread_detach(thread_stdout);
    if (pthread_create(&thread_stderr, nullptr, thread_stderr_func, nullptr) == -1) return -1;
    pthread_detach(thread_stderr);
    return 0;
}
}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_org_opensignalfoundation_iranvpn_tunnel_Tun2SocksNative_nativeStartTun2Socks(
    JNIEnv* env, jclass clazz, jobjectArray args) {
    jsize argc = env->GetArrayLength(args);
    int c_arguments_size = 0;
    for (int i = 0; i < argc; i++) {
        jstring s = (jstring)env->GetObjectArrayElement(args, i);
        const char* utf = env->GetStringUTFChars(s, nullptr);
        c_arguments_size += static_cast<int>(strlen(utf)) + 1;
        env->ReleaseStringUTFChars(s, utf);
        env->DeleteLocalRef(s);
    }
    char* args_buffer = (char*)calloc(c_arguments_size, sizeof(char));
    std::vector<char*> argv(static_cast<size_t>(argc));
    char* current = args_buffer;
    for (int i = 0; i < argc; i++) {
        jstring s = (jstring)env->GetObjectArrayElement(args, i);
        const char* utf = env->GetStringUTFChars(s, nullptr);
        strncpy(current, utf, strlen(utf));
        argv[i] = current;
        env->ReleaseStringUTFChars(s, utf);
        current += strlen(current) + 1;
    }
    if (start_redirecting_stdout_stderr() == -1) {
        __android_log_write(ANDROID_LOG_ERROR, ADBTAG, "Could not redirect stdout/stderr");
    }
    int result = tun2socks_start(argc, argv.data());
    free(args_buffer);
    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL
Java_org_opensignalfoundation_iranvpn_tunnel_Tun2SocksNative_stopTun2Socks(
    JNIEnv*, jclass) {
    tun2socks_terminate();
}

}  // extern "C"
