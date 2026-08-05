package com.shahidkhaleel.cicddemo.service;

import org.springframework.stereotype.Service;

@Service
public class GreetingService {

    private static final String DEFAULT_NAME = "World";

    public String buildGreeting(String name) {
        String trimmed = name == null ? "" : name.trim();
        String subject = trimmed.isEmpty() ? DEFAULT_NAME : trimmed;
        return "Hello, " + subject + "! This page was deployed by the Jenkins -> SonarQube -> Docker -> Minikube pipeline.";
    }
}
