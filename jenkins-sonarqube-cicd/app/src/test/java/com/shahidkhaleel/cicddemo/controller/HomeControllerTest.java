package com.shahidkhaleel.cicddemo.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.model;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.view;

import com.shahidkhaleel.cicddemo.service.GreetingService;
import com.shahidkhaleel.cicddemo.service.VisitCounterService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(HomeController.class)
class HomeControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private GreetingService greetingService;

    @MockBean
    private VisitCounterService visitCounterService;

    @Test
    void homePageRendersGreetingAndVisitCount() throws Exception {
        given(greetingService.buildGreeting(isNull())).willReturn("Hello, World!");
        given(visitCounterService.incrementAndGet()).willReturn(1L);

        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(view().name("index"))
                .andExpect(model().attribute("greeting", "Hello, World!"))
                .andExpect(model().attribute("visitCount", 1L))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Hello, World!")));
    }

    @Test
    void greetPostsNameAndRendersPersonalizedGreeting() throws Exception {
        given(greetingService.buildGreeting(eq("Shahid"))).willReturn("Hello, Shahid!");
        given(visitCounterService.current()).willReturn(5L);

        mockMvc.perform(post("/greet").param("name", "Shahid"))
                .andExpect(status().isOk())
                .andExpect(view().name("index"))
                .andExpect(model().attribute("greeting", "Hello, Shahid!"))
                .andExpect(model().attribute("visitCount", 5L));
    }

    @Test
    void greetWithoutNameStillRendersOk() throws Exception {
        given(greetingService.buildGreeting(any())).willReturn("Hello, World!");
        given(visitCounterService.current()).willReturn(2L);

        mockMvc.perform(post("/greet"))
                .andExpect(status().isOk())
                .andExpect(view().name("index"));
    }
}
