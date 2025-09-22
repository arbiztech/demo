package com.example.demo.controller;

import com.example.demo.entity.SampleEntity;
import com.example.demo.repository.SampleRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.ResponseEntity;

import java.util.List;

/**
 * サンプルデータを操作するためのコントローラ。
 */
@RestController
public class SampleController {

    @Autowired
    private SampleRepository sampleRepository;

    /**
     * データベース内のすべてのサンプルデータを取得する。
     *
     * @return サンプルデータのリスト
     */
    @GetMapping("/samples")
    public List<SampleEntity> getAllSamples() {
        return sampleRepository.findAll();
    }

    /**
     * 新しいサンプルデータを登録する。
     *
     * @param sampleEntity 登録するサンプルデータ
     * @return 登録されたサンプルデータ
     */
    @PostMapping("/samples")
    public ResponseEntity<SampleEntity> createSample(@RequestBody SampleEntity sampleEntity) {
        SampleEntity savedEntity = sampleRepository.save(sampleEntity);
        return ResponseEntity.ok(savedEntity);
    }
}