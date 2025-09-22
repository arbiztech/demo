package com.example.demo.repository;

import com.example.demo.entity.SampleEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

/**
 * サンプルエンティティのリポジトリインターフェース。
 */
@Repository
public interface SampleRepository extends JpaRepository<SampleEntity, Long> {
}