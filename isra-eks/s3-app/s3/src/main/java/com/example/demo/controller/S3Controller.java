package com.example.demo.controller;

import com.example.demo.service.S3Service;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/s3")
public class S3Controller {

    private final S3Service s3Service;

    public S3Controller(S3Service s3Service) {
        this.s3Service = s3Service;
    }

    @PostMapping("/create")
    public String create() {
        s3Service.createFile(
                "irsa-test.txt",
                "Hello from IRSA + Spring Boot + Gradle"
        );
        return "File created";
    }

    @DeleteMapping("/delete")
    public String delete() {
        s3Service.deleteFile("irsa-test.txt");
        return "File deleted";
    }
}

