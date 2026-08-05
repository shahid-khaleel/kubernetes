package com.shahidkhaleel.cicddemo.service;

import java.util.concurrent.atomic.AtomicLong;
import org.springframework.stereotype.Service;

@Service
public class VisitCounterService {

    private final AtomicLong visits = new AtomicLong(0);

    public long incrementAndGet() {
        return visits.incrementAndGet();
    }

    public long current() {
        return visits.get();
    }
}
