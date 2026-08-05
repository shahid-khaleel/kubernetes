package com.shahidkhaleel.cicddemo.controller;

import com.shahidkhaleel.cicddemo.service.GreetingService;
import com.shahidkhaleel.cicddemo.service.VisitCounterService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
public class HomeController {

    private final GreetingService greetingService;
    private final VisitCounterService visitCounterService;

    @Value("${app.version:dev}")
    private String appVersion;

    public HomeController(GreetingService greetingService, VisitCounterService visitCounterService) {
        this.greetingService = greetingService;
        this.visitCounterService = visitCounterService;
    }

    @GetMapping("/")
    public String home(Model model) {
        model.addAttribute("appVersion", appVersion);
        model.addAttribute("visitCount", visitCounterService.incrementAndGet());
        model.addAttribute("greeting", greetingService.buildGreeting(null));
        return "index";
    }

    @PostMapping("/greet")
    public String greet(@RequestParam(name = "name", required = false) String name, Model model) {
        model.addAttribute("appVersion", appVersion);
        model.addAttribute("visitCount", visitCounterService.current());
        model.addAttribute("greeting", greetingService.buildGreeting(name));
        return "index";
    }
}
