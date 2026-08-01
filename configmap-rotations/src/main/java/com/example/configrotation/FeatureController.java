package com.example.configrotation;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * feature.enabled is bound once, at bean creation time. It will NOT change
 * for a running pod even if the underlying ConfigMap (and therefore the
 * mounted /config/application.yaml file) changes afterwards - a new pod
 * (restart) is required to re-read it. This is intentional: it is what lets
 * this demo show the gap between "ConfigMap propagated to the volume" and
 * "application observed the new value".
 */
@RestController
public class FeatureController {

    @Value("${feature.enabled}")
    private boolean featureEnabled;

    private final String podName = System.getenv().getOrDefault("POD_NAME", hostnameFallback());

    @GetMapping("/feature")
    public Map<String, Object> feature() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("feature.enabled", featureEnabled);
        body.put("pod", podName);
        body.put("servedAt", Instant.now().toString());
        return body;
    }

    private static String hostnameFallback() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
